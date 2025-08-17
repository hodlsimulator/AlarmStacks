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
        let id = notification.request.identifier
        if let ts = UserDefaults.standard.object(forKey: "un.expected.\(id)") as? Double {
            let expected = Date(timeIntervalSince1970: ts)
            let delta = Date().timeIntervalSince(expected)
            DiagLog.log(String(format: "UN willPresent id=%@ delta=%.1fs expected=%@", id, delta, expected as CVarArg))
            UserDefaults.standard.removeObject(forKey: "un.expected.\(id)")
        } else {
            DiagLog.log("UN willPresent id=\(id)")
        }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        if let ts = UserDefaults.standard.object(forKey: "un.expected.\(id)") as? Double {
            let expected = Date(timeIntervalSince1970: ts)
            let delta = Date().timeIntervalSince(expected)
            DiagLog.log(String(format: "UN didReceive action=%@ id=%@ delta=%.1fs expected=%@",
                               response.actionIdentifier, id, delta, expected as CVarArg))
            UserDefaults.standard.removeObject(forKey: "un.expected.\(id)")
        } else {
            DiagLog.log("UN didReceive action=\(response.actionIdentifier) id=\(id)")
        }

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
        DiagLog.log("UN schedule (snooze) id=\(id) in \(snoozeMinutes)m thread=\(original.threadIdentifier)")
        try? await center.add(req)
    }
}

@main
struct AlarmStacksApp: App {
    private let notificationDelegate = NotificationDelegate()

    init() {
        NotificationCategories.register()
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .alarmStopOverlay()
                .background(ForegroundRearmCoordinator())
                .preferredAppearance()
                .onOpenURL { DeepLinks.handle($0) }
                .task { try? await AlarmScheduler.shared.requestAuthorizationIfNeeded() }
        }
        .modelContainer(for: [Stack.self, Step.self])
    }
}
