//
//  SnoozeScheduler.swift
//  AlarmStacks
//
//  Created by . . on 8/18/25.
//

import Foundation
import UserNotifications

@MainActor
enum SnoozeScheduler {

    /// Schedules a one-off snooze notification ~1 minute (or N minutes) from *now*,
    /// using a **UNCalendarNotificationTrigger** with seconds and a guard to keep lead ≥ 61s.
    /// Returns the request identifier.
    @discardableResult
    static func scheduleSnooze(
        baseAlarmID: UUID,
        minutes: Int,
        title: String,
        subtitle: String,
        threadKey: String? = nil,
        userInfo: [String: Any] = [:],
        calendar: Calendar = .current
    ) async throws -> String {

        let center = UNUserNotificationCenter.current()
        let requestID = "snooze-\(baseAlarmID.uuidString)"

        // Clean any previous snooze with the same id
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        center.removeDeliveredNotifications(withIdentifiers: [requestID])

        // Compute target with seconds preserved and ensure ≥ 61s lead (iOS may slip <60s calendar triggers)
        let now = Date()
        var target = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        if target.timeIntervalSinceNow < 61 {
            target = now.addingTimeInterval(61)
        }
        // Tiny cushion so we don't end up exactly at the same second
        target.addTimeInterval(0.5)

        // Build content
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = minutes == 1 ? "Snoozed for 1 minute" : "Snoozed for \(minutes) minutes"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "ALARM_CATEGORY" // your existing category
        content.threadIdentifier = threadKey ?? "snooze-\(baseAlarmID.uuidString)"

        var info: [String: Any] = userInfo
        info["snooze"] = true
        info["baseAlarmID"] = baseAlarmID.uuidString
        info["snoozeMinutes"] = minutes
        content.userInfo = info

        // Calendar trigger **with seconds**
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: target)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        // Schedule
        let req = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
        try await center.add(req)

        // Diagnostics (optional)
        UserDefaults.standard.set(target.timeIntervalSince1970, forKey: "un.expected.\(requestID)")
        DiagLog.log("UN snooze id=\(requestID) target=\(DiagLog.f(target)) lead=\(Int(target.timeIntervalSinceNow))s")

        return requestID
    }
}
