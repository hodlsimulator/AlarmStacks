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
#if canImport(ActivityKit)
import ActivityKit
#endif
import os.log
import UserNotifications    

@MainActor
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    private let manager  = AlarmManager.shared
    private let defaults = UserDefaults.standard
    private let log      = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AlarmKit")

    // MARK: Tunables
    private static let minLeadSecondsFirst  = 45
    private static let minLeadSecondsNormal = 12
    private static let postAuthSettleMs: UInt64 = 800

    /// User-tweakable preference kept only for diagnostics.
    private var minReliableLeadForAK: Int {
        let raw = UserDefaults.standard.integer(forKey: "debug.minReliableLeadForAK")
        let value = (raw == 0 ? 75 : raw)
        return max(30, min(600, value))
    }

    /// Optional debug flags (we do not schedule UN here unless AK auth fails entirely).
    private var forceUNFallback: Bool { UserDefaults.standard.bool(forKey: "debug.forceUNFallback") }
    private var alwaysUseAK: Bool { UserDefaults.standard.bool(forKey: "debug.alwaysUseAK") }

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

    // MARK: - Scheduling (AK timers for all steps; no shadows; explicit sound)
    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        let firstRunBeforeAuth = (hasScheduledOnceAK == false)

        do { try await requestAuthorizationIfNeeded() }
        catch {
            // Only if the OS denies AlarmKit entirely, fall back to UN to avoid a total miss.
            DiagLog.log("AK auth failed → UN fallback for stack \(stack.name)")
            return try await UserNotificationScheduler.shared.schedule(stack: stack, calendar: calendar)
        }

        if firstRunBeforeAuth {
            try? await Task.sleep(nanoseconds: Self.postAuthSettleMs * 1_000_000)
        }

        await cancelAll(for: stack)

        // Diagnostics context
        var probeBase = Date()
        var effFirst: Int?
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
            let minLead = firstRunBeforeAuth ? Self.minLeadSecondsFirst : Self.minLeadSecondsNormal
            let raw = max(0, fireDate.timeIntervalSinceNow)
            effFirst = max(minLead, Int(ceil(raw)))
            break
        }
        DiagLog.log("AK decision ctx: forceUN=\(forceUNFallback) alwaysAK=\(alwaysUseAK) firstRun=\(firstRunBeforeAuth) minLeadPref=\(minReliableLeadForAK)s effFirst=\(effFirst ?? -1)s")

        var lastFireDate = Date()
        var akIDs: [UUID] = []
        let minLead = firstRunBeforeAuth ? Self.minLeadSecondsFirst : Self.minLeadSecondsNormal

        for step in stack.sortedSteps where step.isEnabled {
            // Resolve fire date
            let fireDate: Date
            switch step.kind {
            case .fixedTime:
                fireDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
                lastFireDate = fireDate
            case .timer, .relativeToPrev:
                fireDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
                lastFireDate = fireDate
            }

            // Presentation (AlarmKit UI)
            let title: LocalizedStringResource = LocalizedStringResource("\(stack.name) — \(step.title)")
            let alert = makeAlert(title: title, allowSnooze: step.allowSnooze)
            let attrs  = makeAttributes(alert: alert)

            let id = UUID()
            do {
                let now = Date()
                let nowUp = ProcessInfo.processInfo.systemUptime

                // Use a timer **even for fixed-time steps** — this path has rung with banner/sound for you.
                let raw = max(0, fireDate.timeIntervalSinceNow)
                let seconds = max(minLead, Int(ceil(raw)))

                let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> =
                    .timer(
                        duration: TimeInterval(seconds),
                        attributes: attrs,
                        stopIntent: nil,
                        secondaryIntent: nil,
                        sound: .default
                    )

                _ = try await manager.schedule(id: id, configuration: cfg)
                akIDs.append(id)

                log.info("AK schedule id=\(id.uuidString) in \(seconds)s — \(stack.name) / \(step.title)")
                DiagLog.log("AK schedule id=\(id.uuidString) timer in \(seconds)s; stack=\(stack.name); step=\(step.title); target=\(DiagLog.f(fireDate))")

                // Diagnostics expectation
                defaults.set(fireDate.timeIntervalSince1970, forKey: expectedKey(for: id))
                let rec = AKDiag.Record(
                    stackName: stack.name,
                    stepTitle: step.title,
                    scheduledAt: now,
                    scheduledUptime: nowUp,
                    targetDate: fireDate,
                    targetUptime: nowUp + TimeInterval(seconds),
                    seconds: seconds
                )
                AKDiag.save(id: id, record: rec)

            } catch {
                // If AlarmKit scheduling itself throws, bail (optionally UN as last resort).
                for u in akIDs { try? manager.cancel(id: u) }
                DiagLog.log("AK schedule failed → UN fallback for \(stack.name)")
                let ids = try await UserNotificationScheduler.shared.schedule(stack: stack, calendar: calendar)
                await LiveActivityManager.start(for: stack, calendar: calendar)
                return ids
            }
        }

        if firstRunBeforeAuth { hasScheduledOnceAK = true }

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
                AKDiag.remove(id: id)
            }
        }
        defaults.removeObject(forKey: key)

        // Clean up any legacy UN items (safe no-op if none).
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
