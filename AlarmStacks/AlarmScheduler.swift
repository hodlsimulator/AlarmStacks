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
            // We request .alert for general capability, but we **never** use audible/visible alerts for alarms.
            let granted = try await center.requestAuthorization(
                options: [.alert, .badge, .providesAppNotificationSettings]
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

        // ⛔️ Do not pre-start LA here; AK/LA prearm logic elsewhere handles visibility.
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

            // Build **silent, passive** content so UN is never a visible/aloud surface.
            let id = notificationID(stackID: stack.id, stepID: step.id, index: index)
            let content = buildSilentContent(for: step,
                                             stackName: stack.name,
                                             stackID: stack.id.uuidString)

            // Robust trigger selection near "now"
            let lead = max(1, Int(ceil(fireDate.timeIntervalSinceNow)))
            let useInterval = (lead <= 60)

            let trigger: UNNotificationTrigger
            if useInterval {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(lead), repeats: false)
                DiagLog.log("UN schedule (silent) id=\(id) in \(lead)s (interval); stack=\(stack.name); step=\(step.title); target=\(fireDate)")
            } else {
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                DiagLog.log("UN schedule (silent) id=\(id) in ~\(lead)s (calendar); stack=\(stack.name); step=\(step.title); target=\(fireDate)")
            }

            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try await center.add(request)

            // Track expected time so we can compute a delivery delta later.
            UserDefaults.standard.set(fireDate.timeIntervalSince1970, forKey: "un.expected.\(id)")

            identifiers.append(id)
        }

        // ✅ Ensure Live Activity reflects the latest schedule.
        LiveActivityManager.start(for: stack, calendar: calendar)

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

    /// Silent, passive content for **alarm** scheduling via UN (fallback only).
    /// - No banner, no sound, minimal surface. AK/LA provide the UI.
    private func buildSilentContent(for step: Step, stackName: String, stackID: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        // Intentionally blank — keep chrome out of Notification Center.
        content.title = ""
        content.subtitle = ""
        content.body = ""

        // Absolutely no UN audio.
        content.sound = nil

        // Passive = no banner for background deliveries.
        content.interruptionLevel = .passive
        content.relevanceScore = 0

        // Retain thread & category so our delegate can correlate and handle actions silently.
        content.threadIdentifier = "stack-\(stackID)"
        content.categoryIdentifier = NotificationCategoryID.alarm

        content.userInfo = [
            "stackID": stackID,
            "stepID": step.id.uuidString,
            "snoozeMinutes": step.snoozeMinutes,
            "allowSnooze": step.allowSnooze
        ]
        return content
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
}
