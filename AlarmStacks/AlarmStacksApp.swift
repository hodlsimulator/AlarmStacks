//
//  AlarmStacksApp.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData
import UserNotifications

@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        switch response.actionIdentifier {
        case NotificationActionID.snooze:
            await scheduleSnooze(from: content)

        case NotificationActionID.stop, UNNotificationDismissActionIdentifier:
            let thread = content.threadIdentifier
            let pending = await center.pendingNotificationRequests()
            let ids = pending.filter { $0.content.threadIdentifier == thread }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])

        default:
            break
        }
    }

    private func scheduleSnooze(from original: UNNotificationContent) async {
        let center = UNUserNotificationCenter.current()
        let snoozeMinutes = (original.userInfo["snoozeMinutes"] as? Int) ?? 9
        guard (original.userInfo["allowSnooze"] as? Bool) ?? true else { return }

        let content = UNMutableNotificationContent()
        content.title = original.title
        content.subtitle = original.subtitle.isEmpty ? "Snoozed" : "\(original.subtitle) — Snoozed"
        content.body = original.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = original.threadIdentifier
        content.categoryIdentifier = original.categoryIdentifier
        content.userInfo = original.userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, snoozeMinutes * 60)),
                                                        repeats: false)
        let id = "snooze-\(UUID().uuidString)"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(req)
    }
}

@main
struct AlarmStacksApp: App {
    private let notificationDelegate = NotificationDelegate()

    init() {
        // UN actions/categories for the fallback path and snooze/stop actions.
        NotificationCategories.register()
        UNUserNotificationCenter.current().delegate = notificationDelegate
        
        UserDefaults.standard.register(defaults: [
            "debug.forceUNFallback": true,     // ← default to UN path for reliability
            "debug.liveActivitiesEnabled": true
        ])

        // ✅ PRIME AlarmKit authorisation at app launch to avoid a first-run race.
        Task { try? await AlarmScheduler.shared.requestAuthorizationIfNeeded() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .alarmStopOverlay()                        // in-app Stop/Snooze if AK UI isn’t visible
                .background(ForegroundRearmCoordinator())  // re-arm after returning from Settings
                .preferredAppearance()                     // Light/Dark/System
                .onOpenURL { DeepLinks.handle($0) }        // deep links from Live Activity
        }
        .modelContainer(for: [Stack.self, Step.self])
    }
}
