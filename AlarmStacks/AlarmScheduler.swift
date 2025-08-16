//
//  AlarmScheduler.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import UserNotifications
import SwiftData

/// Runs on the main actor to avoid sending non-Sendable SwiftData models across threads (Swift 6 rules).
@MainActor
protocol AlarmScheduling {
    func requestAuthorizationIfNeeded() async throws
    func schedule(stack: Stack, calendar: Calendar) async throws -> [String] // returns identifiers
    func cancelAll(for stack: Stack) async
    func rescheduleAll(stacks: [Stack], calendar: Calendar) async
}

// MARK: - UserNotificationScheduler

@MainActor
final class UserNotificationScheduler: AlarmScheduling {

    /// Convenience singleton so older code can call `AlarmScheduler.shared`.
    static let shared = UserNotificationScheduler()

    init() {}

    func requestAuthorizationIfNeeded() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge, .providesAppNotificationSettings, .criticalAlert]
            )
            if !granted {
                throw NSError(
                    domain: "AlarmStacks",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Notifications permission denied"]
                )
            }
        }
    }

    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        try await requestAuthorizationIfNeeded()

        let center = UNUserNotificationCenter.current()
        await cancelAll(for: stack)

        var identifiers: [String] = []
        let base = Date()
        var lastFireDate: Date = base

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

            let id = notificationID(stackID: stack.id, stepID: step.id, index: index)
            let content = buildContent(
                for: step,
                stackName: stack.name,
                stackID: stack.id.uuidString
            )

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

    func cancelAll(for stack: Stack) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "stack-\(stack.id.uuidString)-"

        let pending = await pendingIDs(prefix: prefix)
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let delivered = await deliveredIDs(prefix: prefix)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        for s in stacks where s.isArmed {
            do { _ = try await schedule(stack: s, calendar: calendar) }
            catch { /* optionally log */ }
        }
    }

    // MARK: - Helpers

    private func buildContent(for step: Step, stackName: String, stackID: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = stackName
        content.subtitle = step.title
        content.body = body(for: step)
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "stack-\(stackID)"

        // Add actions (Stop/Snooze) support.
        content.categoryIdentifier = "ALARM_CATEGORY" // matches the category you register in app start-up
        content.userInfo = [
            "stackID": stackID,
            "stepID": step.id.uuidString,
            "snoozeMinutes": step.effectiveSnoozeMinutes, // ← use effective snooze
            "allowSnooze": step.allowSnooze
        ]

        return content
    }

    private func body(for step: Step) -> String {
        switch step.kind {
        case .fixedTime:
            if let h = step.hour, let m = step.minute {
                return String(format: "Scheduled for %02d:%02d", h, m)
            }
            return "Scheduled"
        case .timer:
            if let s = step.durationSeconds { return "Timer \(format(seconds: s))" }
            return "Timer"
        case .relativeToPrev:
            if let s = step.offsetSeconds { return "Starts \(formatOffset(seconds: s)) after previous" }
            return "Next step"
        }
    }

    private func notificationID(stackID: UUID, stepID: UUID, index: Int) -> String {
        "stack-\(stackID.uuidString)-step-\(stepID.uuidString)-\(index)"
    }

    private func pendingIDs(prefix: String) async -> [String] {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        return requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
    }

    private func deliveredIDs(prefix: String) async -> [String] {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        return delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
    }

    private func format(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private func formatOffset(seconds: Int) -> String {
        seconds >= 0 ? "+\(format(seconds: seconds))" : "−\(format(seconds: -seconds))"
    }
}
