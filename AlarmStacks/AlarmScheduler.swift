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
    @discardableResult
    func schedule(stack: Stack, calendar: Calendar) async throws -> [String] // returns identifiers
    func cancelAll(for stack: Stack) async
    func rescheduleAll(stacks: [Stack], calendar: Calendar) async
}

// Convenience overloads so callers using the protocol don’t need to pass a Calendar every time.
extension AlarmScheduling {
    @discardableResult
    func schedule(stack: Stack) async throws -> [String] {
        try await schedule(stack: stack, calendar: .current)
    }

    func rescheduleAll(stacks: [Stack]) async {
        await rescheduleAll(stacks: stacks, calendar: .current)
    }
}

// MARK: - UserNotificationScheduler

@MainActor
final class UserNotificationScheduler: AlarmScheduling {

    /// Convenience singleton so older code can call `AlarmScheduler.shared`.
    static let shared = UserNotificationScheduler()

    private init() {}

    func requestAuthorizationIfNeeded() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge, .providesAppNotificationSettings]
            )
            if !granted {
                throw NSError(
                    domain: "AlarmStacks",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Notifications permission not granted"]
                )
            }
        case .denied:
            throw NSError(
                domain: "AlarmStacks",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Notifications are denied in Settings."]
            )
        default:
            break
        }
    }

    @discardableResult
    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        _ = try? await requestAuthorizationIfNeeded()

        // ⛔️ Removed preflight LA start — this was causing the “in 23 hours” flash.
        // await LiveActivityManager.start(stack: stack, calendar: calendar)

        let center = UNUserNotificationCenter.current()
        await cancelAll(for: stack)

        var identifiers: [String] = []
        var lastFireDate: Date = Date()

        for (index, step) in stack.sortedSteps.enumerated() where step.isEnabled {
            // Compute fire date
            let fireDate: Date
            switch step.kind {
            case .fixedTime:
                fireDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
                lastFireDate = fireDate
            case .timer, .relativeToPrev:
                fireDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
                lastFireDate = fireDate
            }

            // Build content (per-step snooze overrides Settings)
            let id = notificationID(stackID: stack.id, stepID: step.id, index: index)
            let content = buildContent(for: step, stackName: stack.name, stackID: stack.id.uuidString)

            // Robust trigger selection near "now"
            let lead = max(1, Int(ceil(fireDate.timeIntervalSinceNow)))
            let useInterval = (lead <= 60)

            let trigger: UNNotificationTrigger
            if useInterval {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(lead), repeats: false)
                DiagLog.log("UN schedule id=\(id) in \(lead)s (interval); stack=\(stack.name); step=\(step.title); target=\(fireDate)")
            } else {
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                DiagLog.log("UN schedule id=\(id) in ~\(lead)s (calendar); stack=\(stack.name); step=\(step.title); target=\(fireDate)")
            }

            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try await center.add(request)

            // Track expected time so we can compute a delivery delta later.
            UserDefaults.standard.set(fireDate.timeIntervalSince1970, forKey: "un.expected.\(id)")

            identifiers.append(id)
        }

        // ✅ Start/update the Live Activity only after notifications are scheduled.
        LiveActivityManager.start(stack: stack, calendar: calendar)

        return identifiers
    }

    func cancelAll(for stack: Stack) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "stack-\(stack.id.uuidString)-"

        let pending = await pendingIDs(prefix: prefix)
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for id in pending { UserDefaults.standard.removeObject(forKey: "un.expected.\(id)") }

        let delivered = await deliveredIDs(prefix: prefix)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
        for id in delivered { UserDefaults.standard.removeObject(forKey: "un.expected.\(id)") }
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        for stack in stacks where stack.isArmed {
            _ = try? await schedule(stack: stack, calendar: calendar)
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

        content.categoryIdentifier = "ALARM_CATEGORY"
        content.userInfo = [
            "stackID": stackID,
            "stepID": step.id.uuidString,
            "snoozeMinutes": step.snoozeMinutes,
            "allowSnooze": step.allowSnooze
        ]
        return content
    }

    private func body(for step: Step) -> String {
        switch step.kind {
        case .fixedTime:
            if let h = step.hour, let m = step.minute { return String(format: "Scheduled for %02d:%02d", h, m) }
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
