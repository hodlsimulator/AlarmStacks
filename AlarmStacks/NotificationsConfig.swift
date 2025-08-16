//
//  NotificationsConfig.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import UserNotifications

enum NotificationCategoryID {
    static let alarm = "ALARM_CATEGORY"
}

enum NotificationActionID {
    static let stop   = "ALARM_STOP"
    static let snooze = "ALARM_SNOOZE"
}

enum NotificationCategories {
    static func register() {
        let stop = UNNotificationAction(
            identifier: NotificationActionID.stop,
            title: "Stop",
            options: [.destructive]
        )
        let snooze = UNNotificationAction(
            identifier: NotificationActionID.snooze,
            title: "Snooze",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: NotificationCategoryID.alarm,
            actions: [stop, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
