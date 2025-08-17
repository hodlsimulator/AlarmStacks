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

    // Observe AlarmKit; when alerting -> mark fired + compute delta for diagnostics
    func startObserversIfNeeded() {
        #if canImport(AlarmKit)
        guard observerTask == nil else { return }
        observerTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in manager.alarmUpdates {
                await MainActor.run {
                    self.lastSnapshot = snapshot

                    // Snapshot summary (helps diagnose missing alerts)
                    let counts = Dictionary(grouping: snapshot.map { String(describing: $0.state) }, by: { $0 })
                        .mapValues(\.count)
                        .map { "\($0.key)=\($0.value)" }
                        .sorted()
                        .joined(separator: ", ")
                    DiagLog.log("AK snapshot size=\(snapshot.count) states{\(counts)}")

                    let newAlerting = snapshot.first(where: { $0.state == .alerting })
                    self.alertingAlarm = newAlerting
                    if let a = newAlerting {
                        // Cancel any shadow (legacy safety; harmless if none exist).
                        let center = UNUserNotificationCenter.current()
                        let sid = "shadow-\(a.id.uuidString)"
                        center.removePendingNotificationRequests(withIdentifiers: [sid])
                        center.removeDeliveredNotifications(withIdentifiers: [sid])

                        // Diagnostics: compute delta from expected time (if recorded).
                        let key = "ak.expected.\(a.id.uuidString)"
                        let ts = UserDefaults.standard.double(forKey: key)
                        let appState = UIApplication.shared.applicationState
                        if ts > 0 {
                            let expected = Date(timeIntervalSince1970: ts)
                            let delta = Date().timeIntervalSince(expected)
                            DiagLog.log(String(format: "AK alerting id=%@ appState=%@ delta=%.1fs expected=%@",
                                               a.id.uuidString, String(describing: appState), delta, expected.description))
                            UserDefaults.standard.removeObject(forKey: key)
                        } else {
                            DiagLog.log("AK alerting id=\(a.id.uuidString) (no expected fire time recorded)")
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

    // MARK: - Diagnostics

    func auditAKNow() {
        #if canImport(AlarmKit)
        let auth = String(describing: manager.authorizationState)
        let counts = Dictionary(grouping: lastSnapshot.map { String(describing: $0.state) }, by: { $0 })
            .mapValues(\.count)
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
        DiagLog.log("AK audit auth=\(auth) snapshot=\(lastSnapshot.count) states{\(counts)}")
        #endif
    }
}
