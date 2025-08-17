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
import UserNotifications

@MainActor
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    private let manager  = AlarmManager.shared
    private let defaults = UserDefaults.standard
    private let log      = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AlarmKit")

    // MARK: Tunables
    /// First-install safety margin.
    private static let minLeadSecondsFirst  = 45
    /// Normal margin for subsequent schedules.
    private static let minLeadSecondsNormal = 12
    /// Small settle delay right after authorization completes (first run only).
    private static let postAuthSettleMs: UInt64 = 800
    /// Below this effective lead, AK timers are too flaky on iOS 26 beta → choose UN.
    private static let minReliableLeadForAK = 75

    /// Tracks whether we have scheduled with AK at least once on this install.
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
        case .authorized: return
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

    // MARK: - Scheduling (choose AK or UN — never both)
    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        let firstRunBeforeAuth = (hasScheduledOnceAK == false)

        do { try await requestAuthorizationIfNeeded() }
        catch {
            DiagLog.log("AK auth failed → UN fallback for stack \(stack.name)")
            return try await UserNotificationScheduler.shared.schedule(stack: stack, calendar: calendar)
        }

        if firstRunBeforeAuth {
            try? await Task.sleep(nanoseconds: Self.postAuthSettleMs * 1_000_000)
        }

        await cancelAll(for: stack)

        // Compute FIRST enabled step's effective lead to decide backend.
        var probeBase = Date()
        var effectiveSecondsForFirst: Int?
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
            let firstRun = (hasScheduledOnceAK == false)
            let minLead  = firstRun ? Self.minLeadSecondsFirst : Self.minLeadSecondsNormal
            let raw = max(0, fireDate.timeIntervalSinceNow)
            effectiveSecondsForFirst = max(minLead, Int(ceil(raw)))
            break
        }

        if let eff = effectiveSecondsForFirst, eff < Self.minReliableLeadForAK {
            DiagLog.log("Choosing UN: first-step lead \(eff)s < \(Self.minReliableLeadForAK)s (AK timers jitter on short leads)")
            let ids = try await UserNotificationScheduler.shared.schedule(stack: stack, calendar: calendar)
            await LiveActivityManager.start(for: stack, calendar: calendar)
            return ids
        }

        // Otherwise, use AlarmKit for the stack.
        var lastFireDate = Date()
        var akIDs: [UUID] = []
        let firstRun = (hasScheduledOnceAK == false)
        let minLead  = firstRun ? Self.minLeadSecondsFirst : Self.minLeadSecondsNormal

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

            let title: LocalizedStringResource = LocalizedStringResource("\(stack.name) — \(step.title)")
            let alert = makeAlert(title: title, allowSnooze: step.allowSnooze)
            let attrs  = makeAttributes(alert: alert)

            let id = UUID()
            do {
                let raw = max(0, fireDate.timeIntervalSinceNow)
                let seconds = max(minLead, Int(ceil(raw)))

                log.info("AK schedule id=\(id.uuidString, privacy: .public) in \(seconds, privacy: .public)s — \(stack.name, privacy: .public) / \(step.title, privacy: .public) (firstRun=\(firstRun, privacy: .public))")
                DiagLog.log("AK schedule id=\(id.uuidString) in \(seconds)s; stack=\(stack.name); step=\(step.title); target=\(fireDate)")

                let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> =
                    .timer(duration: TimeInterval(seconds), attributes: attrs)
                _ = try await manager.schedule(id: id, configuration: cfg)
                akIDs.append(id)

                defaults.set(fireDate.timeIntervalSince1970, forKey: expectedKey(for: id))

            } catch {
                for u in akIDs { try? manager.cancel(id: u) }
                DiagLog.log("AK schedule failed → UN fallback for \(stack.name)")
                let ids = try await UserNotificationScheduler.shared.schedule(stack: stack, calendar: calendar)
                await LiveActivityManager.start(for: stack, calendar: calendar)
                return ids
            }
        }

        if firstRun { hasScheduledOnceAK = true }

        await LiveActivityManager.start(for: stack, calendar: calendar)

        defaults.set(akIDs.map(\.uuidString), forKey: storageKey(for: stack))
        return akIDs.map(\.uuidString)
    }

    func cancelAll(for stack: Stack) async {
        let key = storageKey(for: stack)
        for s in (defaults.stringArray(forKey: key) ?? []) {
            if let id = UUID(uuidString: s) {
                try? manager.cancel(id: id)
                defaults.removeObject(forKey: expectedKey(for: id))
            }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["shadow-\(s)"])
            center.removeDeliveredNotifications(withIdentifiers: ["shadow-\(s)"])
        }
        defaults.removeObject(forKey: key)

        await UserNotificationScheduler.shared.cancelAll(for: stack)
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        for s in stacks where s.isArmed { _ = try? await schedule(stack: s, calendar: calendar) }
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
    AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                    tintColor: Color(red: 0.04, green: 0.52, blue: 1.00)) // #0A84FF
}

#endif
