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
import UserNotifications
import os.log

@MainActor
final class AppAlarmKitScheduler {
    static let shared = AppAlarmKitScheduler()

    private let manager  = AlarmManager.shared
    private let defaults = UserDefaults.standard
    private let log      = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AlarmKit")

    private init() {}

    private func storageKey(for stack: Stack) -> String { "alarmkit.ids.\(stack.id.uuidString)" }

    // MARK: - Permissions

    func requestAuthorizationIfNeeded() async throws {
        let currentAuth = self.manager.authorizationState
        self.log.info("AK authState=\(String(describing: currentAuth), privacy: .public)")
        switch currentAuth {
        case .authorized: return
        case .denied:
            throw NSError(domain: "AlarmStacks", code: 1001,
                          userInfo: [NSLocalizedDescriptionKey: "Alarm permission denied"])
        case .notDetermined:
            let state = try await self.manager.requestAuthorization()
            self.log.info("AK requestAuthorization -> \(String(describing: state), privacy: .public)")
            guard state == .authorized else {
                throw NSError(domain: "AlarmStacks", code: 1002,
                              userInfo: [NSLocalizedDescriptionKey: "Alarm permission not granted"])
            }
        @unknown default:
            throw NSError(domain: "AlarmStacks", code: 1003,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown AlarmKit authorisation state"])
        }
    }

    // MARK: - Scheduling (timers only; fixed-time converted to countdown)
    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        // Prefer AK; if it fails, fall back to local UN scheduling.
        do { try await requestAuthorizationIfNeeded() }
        catch {
            self.log.error("AK auth error -> using UN fallback: \(error as NSError, privacy: .public)")
            return try await UN_schedule(stack: stack, calendar: calendar)
        }

        await cancelAll(for: stack) // clear persisted AK IDs and any UN notifs

        var lastFireDate = Date()
        var akIDs: [UUID] = []
        var akFailed = false
        var failureError: NSError?

        for step in stack.sortedSteps where step.isEnabled {
            // Compute target wall-clock time for this step
            let fireDate: Date
            switch step.kind {
            case .fixedTime:
                fireDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
                lastFireDate = fireDate
            case .timer, .relativeToPrev:
                fireDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
                lastFireDate = fireDate
            }

            // Build alert + attributes (IMPORTANT: set .countdown for snooze)
            let title: LocalizedStringResource = LocalizedStringResource("\(stack.name) — \(step.title)")
            let alert = makeAlert(title: title, allowSnooze: step.allowSnooze)
            let attrs  = makeAttributes(alert: alert)

            // Convert to a countdown duration (min 1s) and schedule as TIMER
            let seconds = max(1, Int(ceil(fireDate.timeIntervalSinceNow)))
            let id = UUID()

            do {
                self.log.info("AK scheduling TIMER id=\(id.uuidString, privacy: .public) in \(seconds, privacy: .public)s for \"\(stack.name, privacy: .public) — \(step.title, privacy: .public)\"")
                let cfg: AlarmManager.AlarmConfiguration<AKVoidMetadata> =
                    .timer(duration: TimeInterval(seconds), attributes: attrs)
                _ = try await self.manager.schedule(id: id, configuration: cfg)

                // Persist per-step snooze minutes for in-app overlay labelling.
                AlarmKitSnoozeMap.set(minutes: step.effectiveSnoozeMinutes, for: id)

                akIDs.append(id)
            } catch {
                akFailed = true
                failureError = (error as NSError)
                self.log.error("AK schedule error id=\(id.uuidString, privacy: .public): \(error as NSError, privacy: .public)")
                break
            }
        }

        if akFailed {
            // Roll back anything we placed with AK, then fall back to notifications.
            for u in akIDs {
                try? self.manager.cancel(id: u)
                AlarmKitSnoozeMap.remove(for: u)
            }
            self.log.warning("AK fallback -> UN notifications for stack \"\(stack.name, privacy: .public)\". reason=\(String(describing: failureError), privacy: .public)")
            return try await UN_schedule(stack: stack, calendar: calendar)
        } else {
            let strings = akIDs.map(\.uuidString)
            self.defaults.set(strings, forKey: storageKey(for: stack))
            self.log.info("AK scheduled \(strings.count, privacy: .public) timer(s) for stack \"\(stack.name, privacy: .public)\"")
            return strings
        }
    }

    func cancelAll(for stack: Stack) async {
        // Cancel AK timers we persisted.
        let key = storageKey(for: stack)
        let ids = (self.defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
        for id in ids {
            try? self.manager.cancel(id: id)
        }
        AlarmKitSnoozeMap.removeAll(for: ids)
        self.defaults.removeObject(forKey: key)

        // Also cancel any notifications created by fallback.
        await UN_cancelAll(for: stack)
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        for s in stacks where s.isArmed {
            _ = try? await schedule(stack: s, calendar: calendar)
        }
    }
}

// MARK: - AlarmKit helpers

private struct AKVoidMetadata: AlarmMetadata {}

private func makeAlert(title: LocalizedStringResource, allowSnooze: Bool) -> AlarmPresentation.Alert {
    let stop = AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
    if allowSnooze {
        let snooze = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
        // Explicit snooze behaviour so AK doesn't expect a custom App Intent.
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

private func makeAttributes(alert: AlarmPresentation.Alert) -> AlarmAttributes<AKVoidMetadata> {
    // Calmer blue accent for AK prompts.
    AlarmAttributes(
        presentation: AlarmPresentation(alert: alert),
        tintColor: Color(hex: "#0A84FF")
    )
}

// MARK: - Local UN fallback (decoupled from UserNotificationScheduler)

@MainActor
private func UN_schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    if settings.authorizationStatus == .notDetermined {
        let granted = try await center.requestAuthorization(
            options: [.alert, .sound, .badge, .providesAppNotificationSettings, .criticalAlert]
        )
        if !granted {
            throw NSError(domain: "AlarmStacks",
                          code: 2001,
                          userInfo: [NSLocalizedDescriptionKey: "Notifications permission denied"])
        }
    }

    await UN_cancelAll(for: stack)

    var identifiers: [String] = []
    var lastFireDate: Date = Date()

    for (index, step) in stack.sortedSteps.enumerated() where step.isEnabled {
        let fireDate: Date
        switch step.kind {
        case .fixedTime:
            fireDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
            lastFireDate = fireDate
        case .timer, .relativeToPrev:
            fireDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
            lastFireDate = fireDate
        }

        let id = "stack-\(stack.id.uuidString)-step-\(step.id.uuidString)-\(index)"
        let content = UN_buildContent(for: step, stackName: stack.name, stackID: stack.id.uuidString)

        let trigger: UNNotificationTrigger
        if step.kind == .fixedTime || step.kind == .relativeToPrev {
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            let interval = max(1, Int(fireDate.timeIntervalSinceNow.rounded()))
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(interval), repeats: false)
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
        identifiers.append(id)
    }

    return identifiers
}

@MainActor
private func UN_cancelAll(for stack: Stack) async {
    let center = UNUserNotificationCenter.current()
    let prefix = "stack-\(stack.id.uuidString)-"

    let pending = await UN_pendingIDs(prefix: prefix)
    center.removePendingNotificationRequests(withIdentifiers: pending)

    let delivered = await UN_deliveredIDs(prefix: prefix)
    center.removeDeliveredNotifications(withIdentifiers: delivered)
}

@MainActor
private func UN_pendingIDs(prefix: String) async -> [String] {
    let center = UNUserNotificationCenter.current()
    let requests = await center.pendingNotificationRequests()
    return requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
}

@MainActor
private func UN_deliveredIDs(prefix: String) async -> [String] {
    let center = UNUserNotificationCenter.current()
    let delivered = await center.deliveredNotifications()
    return delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
}

private func UN_buildContent(for step: Step, stackName: String, stackID: String) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = stackName
    content.subtitle = step.title
    content.body = UN_body(for: step)
    content.sound = .default
    content.interruptionLevel = .timeSensitive
    content.threadIdentifier = "stack-\(stackID)"
    content.categoryIdentifier = "ALARM_CATEGORY"
    content.userInfo = [
        "stackID": stackID,
        "stepID": step.id.uuidString,
        "snoozeMinutes": step.effectiveSnoozeMinutes,
        "allowSnooze": step.allowSnooze
    ]
    return content
}

private func UN_body(for step: Step) -> String {
    switch step.kind {
    case .fixedTime:
        if let h = step.hour, let m = step.minute {
            return String(format: "Scheduled for %02d:%02d", h, m)
        }
        return "Scheduled"
    case .timer:
        if let s = step.durationSeconds { return "Timer \(UN_format(seconds: s))" }
        return "Timer"
    case .relativeToPrev:
        if let s = step.offsetSeconds { return "Starts \(UN_formatOffset(seconds: s)) after previous" }
        return "Next step"
    }
}

private func UN_format(seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m \(s)s" }
    return "\(s)s"
}

private func UN_formatOffset(seconds: Int) -> String {
    seconds >= 0 ? "+\(UN_format(seconds: seconds))" : "−\(UN_format(seconds: -seconds))"
}

#endif
