//
//  AlarmStacksApp.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData
import UserNotifications

// Shows notifications (banner + sound) even when the app is in the foreground,
// and handles Snooze/Stop actions.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content

        switch response.actionIdentifier {
        case "ALARM_SNOOZE":
            await scheduleSnooze(from: content)

        case "ALARM_STOP", UNNotificationDismissActionIdentifier:
            // Remove all pending/delivered items in the same thread.
            let thread = content.threadIdentifier
            let pending = await center.pendingNotificationRequests()
            let ids = pending
                .filter { $0.content.threadIdentifier == thread }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])

        default:
            break // normal tap on the banner — add deep link handling here if desired
        }
    }

    private func scheduleSnooze(from original: UNNotificationContent) async {
        let center = UNUserNotificationCenter.current()

        let snoozeMinutes = (original.userInfo["snoozeMinutes"] as? Int) ?? 9
        guard (original.userInfo["allowSnooze"] as? Bool) ?? true else { return }

        let newContent = UNMutableNotificationContent()
        newContent.title = original.title
        newContent.subtitle = original.subtitle.isEmpty ? "Snoozed" : "\(original.subtitle) — Snoozed"
        newContent.body = original.body
        newContent.sound = .default
        newContent.interruptionLevel = .timeSensitive
        newContent.threadIdentifier = original.threadIdentifier
        newContent.categoryIdentifier = original.categoryIdentifier
        newContent.userInfo = original.userInfo

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, snoozeMinutes * 60)),
            repeats: false
        )
        let id = "snooze-\(UUID().uuidString)"
        let req = UNNotificationRequest(identifier: id, content: newContent, trigger: trigger)
        try? await center.add(req)
    }
}

@main
struct AlarmStacksApp: App {
    // Keep a strong reference so the delegate isn't deallocated.
    private let notificationDelegate = NotificationDelegate()

    init() {
        // Register Stop/Snooze actions and install the delegate.
        registerAlarmCategory()
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Prompt for notification (or AlarmKit) permission on first run.
                .task {
                    try? await AlarmScheduler.shared.requestAuthorizationIfNeeded()
                }
        }
        .modelContainer(for: [Stack.self, Step.self])
    }
}

// MARK: - Notification Categories

private func registerAlarmCategory() {
    let center = UNUserNotificationCenter.current()

    let stop = UNNotificationAction(
        identifier: "ALARM_STOP",
        title: "Stop",
        options: [.destructive]
    )
    let snooze = UNNotificationAction(
        identifier: "ALARM_SNOOZE",
        title: "Snooze",
        options: []
    )
    let category = UNNotificationCategory(
        identifier: "ALARM_CATEGORY",
        actions: [stop, snooze],
        intentIdentifiers: [],
        options: [.customDismissAction]
    )
    center.setNotificationCategories([category])
}
