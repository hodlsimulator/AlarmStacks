//
//  AlarmController.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import Combine
#if canImport(AlarmKit)
import AlarmKit
#endif
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AlarmController: ObservableObject {
    static let shared = AlarmController()

    #if canImport(AlarmKit)
    @Published private(set) var alertingAlarm: Alarm?
    @Published private(set) var lastSnapshot: [Alarm] = []
    private let manager = AlarmManager.shared

    /// Store the observer task so we can cancel on background and avoid duplicate streams.
    private var observerTask: Task<Void, Never>?
    #endif

    private var observersStarted = false

    // MARK: - Authorisation
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
        #else
        return
        #endif
    }

    // MARK: - Observe AlarmKit state
    func startObserversIfNeeded() {
        #if canImport(AlarmKit)
        guard observerTask == nil else { return }
        observersStarted = true
        observerTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in manager.alarmUpdates {
                await MainActor.run {
                    let previousID = self.alertingAlarm?.id
                    self.lastSnapshot = snapshot
                    self.alertingAlarm = snapshot.first(where: { $0.state == .alerting })

                    if let a = self.alertingAlarm {
                        let locked = self.isDeviceLocked
                        print("AK ALERTING id=\(a.id) countdown=\(String(describing: a.countdownDuration))")
                        print("AK ALERT PRESENTED (locked? \(locked))")

                        // If the device is LOCKED, cancel the +1s UN mirror so we don't duplicate the Lock Screen alert.
                        if locked {
                            Task { await self.cancelBoostNotification(forAKID: a.id) }
                        }
                    }

                    // Transition change log
                    if previousID != self.alertingAlarm?.id {
                        // could add more diagnostics here
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
        observersStarted = false
        #endif
    }

    // MARK: - Controls
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

    /// Returns the per-step snooze minutes stored when scheduling via AlarmKit (if any).
    func snoozeMinutes(forID id: UUID) -> Int? {
        #if canImport(AlarmKit)
        return AlarmKitSnoozeMap.minutes(for: id)
        #else
        return nil
        #endif
    }

    // MARK: - Helpers

    /// Best-effort: true when the device is locked (protected data unavailable).
    private var isDeviceLocked: Bool {
        #if canImport(UIKit)
        return !UIApplication.shared.isProtectedDataAvailable
        #else
        return false
        #endif
    }

    /// Cancel the pending UN “boost” notification whose id is "ak-boost-<AKUUID>"
    private func cancelBoostNotification(forAKID id: UUID) async {
        let center = UNUserNotificationCenter.current()
        let ident = "ak-boost-\(id.uuidString)"
        // Remove pending; also remove delivered in case it squeaked through.
        center.removePendingNotificationRequests(withIdentifiers: [ident])
        center.removeDeliveredNotifications(withIdentifiers: [ident])
    }
}
