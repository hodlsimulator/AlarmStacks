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
        // If AlarmKit supports duration-based countdowns in your build, call that overload here.
        // Otherwise we trigger the default AK countdown. The UN fallback path already uses per-step minutes.
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
}
