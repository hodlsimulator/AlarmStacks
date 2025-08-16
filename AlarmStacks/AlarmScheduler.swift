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
final class LocalNotificationScheduler {

    /// Convenience singleton so older code can call `AlarmScheduler.shared` via the alias.
    static let shared = LocalNotificationScheduler()

    init() {}

    func requestAuthorizationIfNeeded() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            // IMPORTANT: no `.criticalAlert` (needs entitlement, can cause false "not granted")
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
            // Surface denial so callers can decide to show an explainer or a Settings deep link.
            throw NSError(
                domain: "AlarmStacks",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Notifications are denied in Settings."]
            )
        default:
            break
        }
    }

    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        // Try to ensure permission. If denied, we'll still attempt to schedule (some systems
        // allow scheduling but won't deliver). Callers should re-schedule after user changes settings.
        _ = try? await requestAuthorizationIfNeeded()

        let center = UNUserNotificationCenter.current()
        await cancelAll(for: stack)

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

        // Add actions (Stop/Snooze) support (matches registration in app start-up).
        content.categoryIdentifier = "ALARM_CATEGORY"
        content.userInfo = [
            "stackID": stackID,
            "stepID": step.id.uuidString,
            "snoozeMinutes": step.effectiveSnoozeMinutes, // per-step
            "allowSnooze": step.allowSnooze
        ]

        return content
    }

    private func body(for step: Step) -> String {
        switch step.kind {
        case .fixedTime:
            if let h = step.hour, let m = step.minute {
                // Include weekday summary if present, to help debugging delivery expectations.
                let days = daysText(for: step)
                return days.isEmpty ? String(format: "Scheduled for %02d:%02d", h, m)
                                    : String(format: "Scheduled %02d:%02d • %@", h, m, days)
            }
            return "Scheduled"
        case .timer:
            if let s = step.durationSeconds {
                if let n = step.everyNDays, n > 1 {
                    return "Timer \(format(seconds: s)) • every \(n) days"
                }
                return "Timer \(format(seconds: s))"
            }
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

    private func daysText(for step: Step) -> String {
        let map = [2:"Mon",3:"Tue",4:"Wed",5:"Thu",6:"Fri",7:"Sat",1:"Sun"]
        let chosen: [Int]
        if let arr = step.weekdays, !arr.isEmpty {
            chosen = arr
        } else if let one = step.weekday {
            chosen = [one]
        } else {
            return ""
        }
        let set = Set(chosen)
        if set.count == 7 { return "Every day" }
        if set == Set([2,3,4,5,6]) { return "Weekdays" }
        if set == Set([1,7]) { return "Weekend" }
        let order = [2,3,4,5,6,7,1]
        return order.filter { set.contains($0) }.compactMap { map[$0] }.joined(separator: " ")
    }
}
