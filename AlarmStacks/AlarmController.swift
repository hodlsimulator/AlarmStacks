//
//  AlarmController.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import Combine
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
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

    // Observe AlarmKit; when alerting -> mark fired + compute delta/app-state for diagnostics
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
                        // Cancel any shadow (legacy safety; harmless if none exist).
                        let center = UNUserNotificationCenter.current()
                        let sid = "shadow-\(a.id.uuidString)"
                        center.removePendingNotificationRequests(withIdentifiers: [sid])
                        center.removeDeliveredNotifications(withIdentifiers: [sid])

                        // Diagnostics: compute delta from expected time (if recorded) and include app state.
                        let key = "ak.expected.\(a.id.uuidString)"
                        let ts = UserDefaults.standard.double(forKey: key)

                        #if canImport(UIKit)
                        let appState: String = {
                            switch UIApplication.shared.applicationState {
                            case .active:     return "active"
                            case .inactive:   return "inactive"
                            case .background: return "background"
                            @unknown default: return "unknown"
                            }
                        }()
                        #else
                        let appState = "n/a"
                        #endif

                        if ts > 0 {
                            let expected = Date(timeIntervalSince1970: ts)
                            let delta = Date().timeIntervalSince(expected)
                            DiagLog.log(String(format: "AK alerting id=%@ appState=%@ delta=%.1fs expected=%@",
                                               a.id.uuidString, appState, delta, expected as CVarArg))
                            UserDefaults.standard.removeObject(forKey: key)
                        } else {
                            DiagLog.log("AK alerting id=\(a.id.uuidString) appState=\(appState) (no expected fire time recorded)")
                        }

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
