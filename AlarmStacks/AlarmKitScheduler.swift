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

    // Tunables
    private static let minLeadSeconds = 12   // avoid first-run races
    private var shadowEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debug.shadowFallbackEnabled") // default OFF
    }
    private static let shadowDelaySeconds = 8 // fire + 8s (cancelled if AK alerts)

    private init() {}

    private func storageKey(for stack: Stack) -> String { "alarmkit.ids.\(stack.id.uuidString)" }

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

    // MARK: - Scheduling (AlarmKit timers)
    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        do { try await requestAuthorizationIfNeeded() }
        catch {
            // Hard fallback: if AK auth itself fails, caller’s UN path will handle.
            return try await UserNotificationScheduler.shared.schedule(stack: stack, calendar: calendar)
        }

        await cancelAll(for: stack)

        var lastFireDate = Date()
        var akIDs: [UUID] = []

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
                let raw = fireDate.timeIntervalSinceNow
                let seconds = max(Self.minLeadSeconds, Int(ceil(raw)))

                log.info("AK schedule id=\(id.uuidString, privacy: .public) in \(seconds, privacy: .public)s — \(stack.name, privacy: .public) / \(step.title, privacy: .public)")

                let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> =
                    .timer(duration: TimeInterval(seconds), attributes: attrs)
                _ = try await manager.schedule(id: id, configuration: cfg)
                akIDs.append(id)

                // Optional shadow (debug only). We schedule late and cancel on .alerting.
                if shadowEnabled {
                    await scheduleShadowBanner(for: id,
                                               stack: stack,
                                               step: step,
                                               fireDate: Date().addingTimeInterval(TimeInterval(seconds)),
                                               delaySeconds: Self.shadowDelaySeconds)
                }

            } catch {
                // Roll back anything we placed with AK, then UN fallback for the whole stack.
                for u in akIDs { try? manager.cancel(id: u) }
                return try await UserNotificationScheduler.shared.schedule(stack: stack, calendar: calendar)
            }
        }

        // Start/refresh Live Activity & widget bridge (safe no-op if disabled).
        await LiveActivityManager.start(for: stack, calendar: calendar)
        defaults.set(akIDs.map(\.uuidString), forKey: storageKey(for: stack))
        return akIDs.map(\.uuidString)
    }

    func cancelAll(for stack: Stack) async {
        let key = storageKey(for: stack)
        for s in (defaults.stringArray(forKey: key) ?? []) {
            if let id = UUID(uuidString: s) { try? manager.cancel(id: id) }
            // Clean any pending/delivered shadow (if it was enabled)
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

    // MARK: - Shadow UN banner (debug only)
    private func scheduleShadowBanner(for id: UUID,
                                      stack: Stack,
                                      step: Step,
                                      fireDate: Date,
                                      delaySeconds: Int) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = stack.name
        content.subtitle = step.title
        content.body = "Backup alert in case the alarm UI didn’t appear."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "ALARM_CATEGORY"
        content.threadIdentifier = "ak-\(id.uuidString)"
        content.userInfo = [
            "stackID": stack.id.uuidString,
            "stepID": step.id.uuidString,
            "snoozeMinutes": step.snoozeMinutes,
            "allowSnooze": step.allowSnooze
        ]

        let t = max(1, Int(ceil(fireDate.timeIntervalSinceNow))) + max(0, delaySeconds)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(t), repeats: false)
        let req = UNNotificationRequest(identifier: "shadow-\(id.uuidString)", content: content, trigger: trigger)
        try? await center.add(req)
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
