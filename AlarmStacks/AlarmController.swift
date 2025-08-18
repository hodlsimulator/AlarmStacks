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
    private var observerTask: Task<Void, Never>?
    #endif

    // MARK: - Authorization

    func ensureAuthorised() async throws {
        #if canImport(AlarmKit)
        switch manager.authorizationState {
        case .authorized: break
        case .notDetermined: _ = try await manager.requestAuthorization()
        case .denied:
            throw NSError(
                domain: "AlarmStacks",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Alarm permission denied in Settings."]
            )
        @unknown default: break
        }
        #endif
    }

    // MARK: - Observing AlarmKit

    func startObserversIfNeeded() {
        #if canImport(AlarmKit)
        guard observerTask == nil else { return }

        observerTask = Task { [weak self] in
            guard let self else { return }

            for await snapshot in manager.alarmUpdates {
                await MainActor.run {
                    self.lastSnapshot = snapshot

                    if let a = snapshot.first(where: { $0.state == .alerting }) {
                        self.alertingAlarm = a

                        // --- Diagnostics ---
                        let appStateDesc: String = {
                            #if canImport(UIKit)
                            let raw = UIApplication.shared.applicationState.rawValue
                            return "UIApplicationState(rawValue: \(raw))"
                            #else
                            return "unknown"
                            #endif
                        }()

                        let key = "ak.expected.\(a.id.uuidString)"
                        let ts = UserDefaults.standard.double(forKey: key)
                        if ts > 0 {
                            let expected = Date(timeIntervalSince1970: ts)
                            let wallDelta = Date().timeIntervalSince(expected)

                            if let rec = AKDiag.load(id: a.id) {
                                let upNow = ProcessInfo.processInfo.systemUptime
                                let upDelta = upNow - rec.targetUptime
                                DiagLog.log(String(
                                    format: "AK alerting id=%@ appState=%@ wallΔ=%.3fs upΔ=%.3fs targetLocal=%@",
                                    a.id.uuidString, appStateDesc, wallDelta, upDelta, DiagLog.f(expected)
                                ))
                                AKDiag.remove(id: a.id)
                            } else {
                                DiagLog.log(String(
                                    format: "AK alerting id=%@ appState=%@ wallΔ=%.3fs targetLocal=%@",
                                    a.id.uuidString, appStateDesc, wallDelta, DiagLog.f(expected)
                                ))
                            }
                            UserDefaults.standard.removeObject(forKey: key)
                        } else {
                            DiagLog.log("AK alerting id=\(a.id.uuidString) appState=\(appStateDesc) (no expected fire time recorded)")
                        }
                        // -----------------------------------------

                        // Live Activity stamp
                        Task { await LiveActivityManager.markFiredNow() }
                    } else {
                        self.alertingAlarm = nil
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

    // MARK: - Diagnostics

    func auditAKNow() {
        #if canImport(AlarmKit)
        let counts = Dictionary(grouping: lastSnapshot, by: { $0.state }).mapValues { $0.count }
        let summary = counts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        DiagLog.log("AK snapshot size=\(lastSnapshot.count) states{\(summary)}")
        #endif
    }
}
