//
//  AlarmController.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import Combine
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

@MainActor
final class AlarmController: ObservableObject {
    static let shared = AlarmController()

    #if canImport(AlarmKit)
    @Published private(set) var alertingAlarm: Alarm?
    @Published private(set) var lastSnapshot: [Alarm] = []
    private let manager = AlarmManager.shared
    private var observerTask: Task<Void, Never>?
    #endif

    func ensureAuthorised() async throws {
        #if canImport(AlarmKit)
        switch manager.authorizationState {
        case .authorized: break
        case .notDetermined: _ = try await manager.requestAuthorization()
        case .denied:
            throw NSError(domain: "AlarmStacks", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Alarm permission denied in Settings."])
        @unknown default: break
        }
        #endif
    }

    // Observe AlarmKit; when alerting -> cancel shadow + mark fired time for LA UI
    func startObserversIfNeeded() {
        #if canImport(AlarmKit)
        guard observerTask == nil else { return }
        observerTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in manager.alarmUpdates {
                await MainActor.run {
                    self.lastSnapshot = snapshot
                    let newAlerting = snapshot.first(where: { $0.state == .alerting })
                    self.alertingAlarm = newAlerting
                    if let a = newAlerting {
                        // Kill any shadow notification for this AK id.
                        let center = UNUserNotificationCenter.current()
                        let sid = "shadow-\(a.id.uuidString)"
                        center.removePendingNotificationRequests(withIdentifiers: [sid])
                        center.removeDeliveredNotifications(withIdentifiers: [sid])

                        // Tell Live Activity to freeze at fired time.
                        Task { await LiveActivityManager.markFiredNow() }
                    }
                }
            }
        }
        #endif
    }

    func cancelObservers() {
        #if canImport(AlarmKit)
        observerTask?.cancel()
        observerTask = nil
        #endif
    }

    func stop(_ id: UUID) {
        #if canImport(AlarmKit)
        try? manager.stop(id: id)
        #endif
    }

    func snooze(_ id: UUID) {
        #if canImport(AlarmKit)
        try? manager.countdown(id: id)
        #endif
    }
}
