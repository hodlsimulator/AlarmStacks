//
//  AlarmKitScheduler.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

#if canImport(AlarmKit)

import Foundation
import SwiftData
import SwiftUI
import AlarmKit
import os.log

@MainActor
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    private let manager  = AlarmManager.shared
    private let defaults = UserDefaults.standard
    private let log      = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AlarmKit")

    // MARK: Tunables
    private static let minLeadSecondsFirst  = 45
    private static let minLeadSecondsNormal = 20
    private static let protectedWindowSecs  = 8
    private static let postAuthSettleMs: UInt64 = 800

    private var hasScheduledOnceAK: Bool {
        get { defaults.bool(forKey: "ak.hasScheduledOnce") }
        set { defaults.set(newValue, forKey: "ak.hasScheduledOnce") }
    }

    private init() {}

    private func storageKey(for stack: Stack) -> String { "alarmkit.ids.\(stack.id.uuidString)" }
    private func expectedKey(for id: UUID) -> String { "ak.expected.\(id.uuidString)" }

    // MARK: - Permissions

    func requestAuthorizationIfNeeded() async throws {
        switch manager.authorizationState {
        case .authorized:
            return
        case .denied:
            throw NSError(domain: "AlarmStacks", code: 1001,
                          userInfo: [NSLocalizedDescriptionKey: "Alarm permission denied"])
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            guard state == .authorized else {
                throw NSError(domain: "AlarmStacks", code: 1002,
                              userInfo: [NSLocalizedDescriptionKey: "Alarm permission not granted"])
            }
        @unknown default:
            throw NSError(domain: "AlarmStacks", code: 1003,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown AlarmKit authorisation state"])
        }
    }

    // MARK: - Scheduling (single AK timer per step)

    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        try await requestAuthorizationIfNeeded()

        // Don’t stomp a timer that’s about to fire.
        if let imminent = nextEnabledStepFireDate(for: stack, calendar: calendar),
           imminent.timeIntervalSinceNow <= TimeInterval(Self.protectedWindowSecs) {
            DiagLog.log("AK schedule SKIP (protected window) next=\(DiagLog.f(imminent)) (~\(Int(imminent.timeIntervalSinceNow))s)")
            return defaults.stringArray(forKey: storageKey(for: stack)) ?? []
        }

        // First-auth UI jitter
        if hasScheduledOnceAK == false {
            try? await Task.sleep(nanoseconds: Self.postAuthSettleMs * 1_000_000)
        }

        await cancelAll(for: stack)

        var lastFireDate = Date()
        var akIDs: [UUID] = []

        let firstRun = (hasScheduledOnceAK == false)
        let minLead  = firstRun ? Self.minLeadSecondsFirst : Self.minLeadSecondsNormal

        // Log effective lead for the first enabled step
        if let eff = effectiveLeadSeconds(for: stack, calendar: calendar, minLead: minLead) {
            DiagLog.log("AK decision ctx: firstRun=\(firstRun) minLeadPref=0s effFirst=\(eff)s")
        } else {
            DiagLog.log("AK decision ctx: firstRun=\(firstRun) (no enabled steps)")
        }

        for step in stack.sortedSteps where step.isEnabled {
            let fireDate: Date
            switch step.kind {
            case .fixedTime:
                fireDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
                lastFireDate = fireDate
            case .timer, .relativeToPrev:
                fireDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
                lastFireDate = fireDate
            }

            let now = Date()
            let secondsRaw = max(0, fireDate.timeIntervalSince(now))
            let seconds = max(minLead, Int(ceil(secondsRaw)))

            let title: LocalizedStringResource = LocalizedStringResource("\(stack.name) — \(step.title)")
            let alert = makeAlert(title: title, allowSnooze: step.allowSnooze)
            let attrs  = makeAttributes(alert: alert)

            let id = UUID()
            log.info("AK schedule id=\(id.uuidString, privacy: .public) timer in \(seconds, privacy: .public)s; stack=\(stack.name, privacy: .public); step=\(step.title, privacy: .public); target=\(fireDate as NSDate, privacy: .public)")
            DiagLog.log("AK schedule id=\(id.uuidString) timer in \(seconds)s; stack=\(stack.name); step=\(step.title); target=\(DiagLog.f(fireDate))")

            // Persist expected times for diagnostics
            defaults.set(fireDate.timeIntervalSince1970, forKey: expectedKey(for: id))

            // Single AK timer per step (no retries)
            let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> =
                .timer(duration: TimeInterval(seconds), attributes: attrs)
            _ = try await manager.schedule(id: id, configuration: cfg)

            akIDs.append(id)
        }

        if firstRun { hasScheduledOnceAK = true }
        defaults.set(akIDs.map(\.uuidString), forKey: storageKey(for: stack))

        await LiveActivityManager.start(for: stack, calendar: calendar)
        return akIDs.map(\.uuidString)
    }

    func cancelAll(for stack: Stack) async {
        let key = storageKey(for: stack)
        for s in (defaults.stringArray(forKey: key) ?? []) {
            if let id = UUID(uuidString: s) {
                try? manager.cancel(id: id)
                defaults.removeObject(forKey: expectedKey(for: id))
            }
        }
        defaults.removeObject(forKey: key)
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        for s in stacks where s.isArmed { _ = try? await schedule(stack: s, calendar: calendar) }
    }

    // MARK: Helpers

    private func nextEnabledStepFireDate(for stack: Stack, calendar: Calendar) -> Date? {
        var base = Date()
        for step in stack.sortedSteps where step.isEnabled {
            switch step.kind {
            case .fixedTime:
                if let d = try? step.nextFireDate(basedOn: Date(), calendar: calendar) { return d }
                else { return nil }
            case .timer, .relativeToPrev:
                if let d = try? step.nextFireDate(basedOn: base, calendar: calendar) { return d }
                else { return nil }
            }
        }
        return nil
    }

    private func effectiveLeadSeconds(for stack: Stack, calendar: Calendar, minLead: Int) -> Int? {
        var probeBase = Date()
        for step in stack.sortedSteps where step.isEnabled {
            let fireDate: Date
            switch step.kind {
            case .fixedTime:
                fireDate = (try? step.nextFireDate(basedOn: Date(), calendar: calendar)) ?? Date().addingTimeInterval(3600)
                probeBase = fireDate
            case .timer, .relativeToPrev:
                fireDate = (try? step.nextFireDate(basedOn: probeBase, calendar: calendar)) ?? Date().addingTimeInterval(3600)
                probeBase = fireDate
            }
            let raw = max(0, fireDate.timeIntervalSinceNow)
            return max(minLead, Int(ceil(raw)))
        }
        return nil
    }
}

// MARK: - AlarmKit helpers

nonisolated struct EmptyMetadata: AlarmMetadata {}

private func makeAlert(title: LocalizedStringResource, allowSnooze: Bool) -> AlarmPresentation.Alert {
    let stop = AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
    if allowSnooze {
        let snooze = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
        return AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: snooze, secondaryButtonBehavior: .countdown)
    } else {
        return AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: nil, secondaryButtonBehavior: nil)
    }
}

private func makeAttributes(alert: AlarmPresentation.Alert) -> AlarmAttributes<EmptyMetadata> {
    AlarmAttributes(
        presentation: AlarmPresentation(alert: alert),
        tintColor: Color(red: 0.04, green: 0.52, blue: 1.00) // #0A84FF
    )
}

#endif
