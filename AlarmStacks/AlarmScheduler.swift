//
//  AlarmScheduler.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import Combine
import UserNotifications

@MainActor
final class AlarmScheduler: ObservableObject {
    static let shared = AlarmScheduler()
    private init() { }

    enum SchedulerError: Error { case unauthorized }

    // Ask for notification permission if needed.
    func requestAuthorizationIfNeeded() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            let granted: Bool = await withCheckedContinuation { cont in
                center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                    cont.resume(returning: ok)
                }
            }
            guard granted else { throw SchedulerError.unauthorized }
        default:
            throw SchedulerError.unauthorized
        }
    }

    /// Schedule every step in a stack as local notifications.
    /// - Timer steps use UNTimeIntervalNotificationTrigger.
    /// - Time-of-day steps repeat daily or on specified weekdays.
    /// Returns the identifiers you can later cancel.
    func schedule(stack: AlarmStack, startAt: Date = .now) async throws -> [UUID] {
        try await requestAuthorizationIfNeeded()
        var scheduled: [UUID] = []

        for step in stack.steps {
            if let h = step.hour, let m = step.minute {
                if step.weekdays.isEmpty {
                    let id = UUID()
                    var comps = DateComponents()
                    comps.hour = h
                    comps.minute = m
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                    let req = UNNotificationRequest(identifier: id.uuidString,
                                                    content: makeContent(title: step.title),
                                                    trigger: trigger)
                    try await addRequest(req)
                    scheduled.append(id)
                } else {
                    // 0=Sun…6=Sat in our model → 1…7 for Calendar
                    for wd in step.weekdays {
                        let id = UUID()
                        var comps = DateComponents()
                        comps.weekday = wd + 1
                        comps.hour = h
                        comps.minute = m
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                        let req = UNNotificationRequest(identifier: id.uuidString,
                                                        content: makeContent(title: step.title),
                                                        trigger: trigger)
                        try await addRequest(req)
                        scheduled.append(id)
                    }
                }
            } else if step.durationSeconds > 0 {
                let id = UUID()
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(step.durationSeconds),
                                                                repeats: false)
                let req = UNNotificationRequest(identifier: id.uuidString,
                                                content: makeContent(title: step.title),
                                                trigger: trigger)
                try await addRequest(req)
                scheduled.append(id)
            }
        }
        return scheduled
    }

    func cancel(alarmIDs: [UUID]) {
        let ids = alarmIDs.map { $0.uuidString }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Helpers
    private func makeContent(title: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = "Alarm Stacks"
        c.sound = .default
        return c
    }

    private func addRequest(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { err in
                if let err = err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }
}
