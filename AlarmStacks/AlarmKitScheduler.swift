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
#if canImport(ActivityKit)
import ActivityKit
#endif

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

    // MARK: - Scheduling (AlarmKit timers for all steps; UN only if AK auth fails)
    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        let firstRunBeforeAuth = (hasScheduledOnceAK == false)

        do { try await requestAuthorizationIfNeeded() }
        catch {
            DiagLog.log("AK auth failed → UN fallback for stack \(stack.name)")
            return try await UserNotificationScheduler.shared.schedule(stack: stack, calendar: calendar)
        }

        if firstRunBeforeAuth {
            // Small settle to avoid any post-permission race on first-ever schedule.
            try? await Task.sleep(nanoseconds: Self.postAuthSettleMs * 1_000_000)
        }

        await cancelAll(for: stack)

        // Compute the first enabled step's fire date (for Live Activity kickoff + diagnostics).
        var probeBase = Date()
        var firstFireDate: Date?
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
            firstFireDate = fireDate
            let firstRun = (hasScheduledOnceAK == false)
            let minLead  = firstRun ? Self.minLeadSecondsFirst : Self.minLeadSecondsNormal
            let raw = max(0, fireDate.timeIntervalSinceNow)
            effectiveSecondsForFirst = max(minLead, Int(ceil(raw)))
            break
        }

        DiagLog.log("AK decision ctx: forceUN=false alwaysAK=true firstRun=\(firstRunBeforeAuth) minLeadPref=0s effFirst=\(effectiveSecondsForFirst ?? -1)s")

        // Ensure the Dynamic Island / Live Activity starts once we know the first target.
        if let _ = firstFireDate {
            await LiveActivityManager.start(for: stack, calendar: calendar)
        }

        // Use AlarmKit timers for every enabled step (convert fixed-time into a timer).
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
                let now = Date()
                let nowUp = ProcessInfo.processInfo.systemUptime
                let raw = max(0, fireDate.timeIntervalSinceNow)
                let seconds = max(minLead, Int(ceil(raw)))

                log.info("AK schedule id=\(id.uuidString, privacy: .public) timer in \(seconds, privacy: .public)s — \(stack.name, privacy: .public) / \(step.title, privacy: .public)")
                DiagLog.log("AK schedule id=\(id.uuidString) timer in \(seconds)s; stack=\(stack.name); step=\(step.title); target=\(DiagLog.f(fireDate))")

                // IMPORTANT: your AlarmKit build uses the .timer(duration:attributes:) signature.
                let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> =
                    .timer(duration: TimeInterval(seconds), attributes: attrs)
                _ = try await manager.schedule(id: id, configuration: cfg)
                akIDs.append(id)

                // Persist expected times (both clocks) for watchdog diagnostics.
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

                // Watchdog: if record still exists well after target, note a MISS.
                let wait = seconds + 12 + 5
                Task.detached { [id] in
                    try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                    await MainActor.run {
                        if let rec2 = AKDiag.load(id: id) {
                            let upStr = String(format: "%.3f", rec2.targetUptime)
                            DiagLog.log("AK watchdog MISS id=\(id.uuidString) expectLocal=\(DiagLog.f(rec2.targetDate)) expectUp=\(upStr)s")
                        }
                    }
                }

            } catch {
                // If AK scheduling fails, clean up and fall back to UN scheduling for this stack.
                for u in akIDs { try? manager.cancel(id: u) }
                DiagLog.log("AK schedule failed → UN fallback for \(stack.name)")
                let ids = try await UserNotificationScheduler.shared.schedule(stack: stack, calendar: calendar)
                await LiveActivityManager.start(for: stack, calendar: calendar)
                return ids
            }
        }

        if firstRun { hasScheduledOnceAK = true }

        // Redundant safety to keep Live Activity alive.
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
            // Clean up any legacy UN ids that might remain from past builds.
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["fallback-\(s)","shadow-\(s)"])
            center.removeDeliveredNotifications(withIdentifiers: ["fallback-\(s)","shadow-\(s)"])
        }
        defaults.removeObject(forKey: key)

        await UserNotificationScheduler.shared.cancelAll(for: stack)
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        for s in stacks where s.isArmed {
            _ = try? await schedule(stack: s, calendar: calendar)
        }
    }
}

// MARK: - AlarmKit helpers

nonisolated struct EmptyMetadata: AlarmMetadata {}

private func makeAlert(title: LocalizedStringResource, allowSnooze: Bool) -> AlarmPresentation.Alert {
    let stop = AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
    if allowSnooze {
        let snooze = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
        return AlarmPresentation.Alert(
            title: title,
            stopButton: stop,
            secondaryButton: snooze,
            secondaryButtonBehavior: .countdown
        )
    } else {
        return AlarmPresentation.Alert(
            title: title,
            stopButton: stop,
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
    }
}

private func makeAttributes(alert: AlarmPresentation.Alert) -> AlarmAttributes<EmptyMetadata> {
    AlarmAttributes(
        presentation: AlarmPresentation(alert: alert),
        tintColor: Color(red: 0.04, green: 0.52, blue: 1.00) // #0A84FF
    )
}

#endif
