//
//  AlarmStacksApp.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData
import UserNotifications

// Shows notifications (banner + sound) even when the app is in the foreground.
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
        // Handle taps if you want to deep-link to a stack/step later.
    }
}

@main
struct AlarmStacksApp: App {
    // Keep a strong reference so the delegate isn't deallocated.
    private let notificationDelegate = NotificationDelegate()

    init() {
        // Install the delegate at launch.
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Prompt for notification permission on first run (safe to call repeatedly).
                .task {
                    try? await AlarmScheduler.shared.requestAuthorizationIfNeeded()
                }
        }
        // Use SwiftData with the current models.
        .modelContainer(for: [Stack.self, Step.self])
    }
}
