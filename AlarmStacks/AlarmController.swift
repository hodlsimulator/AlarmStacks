//
//  AlarmController.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

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

@MainActor
final class AlarmController: ObservableObject {
    static let shared = AlarmController()

    #if canImport(AlarmKit)
    @Published private(set) var alertingAlarm: Alarm?
    @Published private(set) var lastSnapshot: [Alarm] = []
    private let manager = AlarmManager.shared
    /// Store the observer Task so we can cancel it and avoid duplicate streams.
    private var observerTask: Task<Void, Never>?
    #endif

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
        #endif
    }

    // MARK: - Observe AlarmKit state
    func startObserversIfNeeded() {
        #if canImport(AlarmKit)
        guard observerTask == nil else { return }
        observerTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in manager.alarmUpdates {
                await MainActor.run {
                    self.lastSnapshot = snapshot
                    self.alertingAlarm = snapshot.first(where: { $0.state == .alerting })
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
}
