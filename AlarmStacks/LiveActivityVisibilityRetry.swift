//
//  LiveActivityVisibilityRetry.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
import ActivityKit
import UIKit

/// Ensures a Live Activity becomes visible when we detect a "visibility" failure,
/// and avoids making a request while the app is foreground & near-fire (which often throws).
/// Intentionally **not** @MainActor so callers anywhere can invoke it; we hop to Main for ActivityKit work.
final class LiveActivityVisibilityRetry {

    static let shared = LiveActivityVisibilityRetry()

    /// Defer if the next fire is within this window **and** the app is active.
    private let deferThreshold: TimeInterval = 90 // seconds

    private init() {
        // Install observers on first use.
        Task { @MainActor in
            self.installObserversIfNeeded()
        }
    }

    // MARK: - Public API

    /// Original ordering used at some call sites.
    func enqueue(reason: String = "visibility", stackID: String) {
        MiniDiag.log("[ACT] LA request failed (\(reason)); queue→attempt stack=\(stackID)")
        Task { @MainActor in
            // If there isn't already a more specific closure queued, fall back to a generic "start or update" attempt.
            if self.pending[stackID] == nil {
                self.pending[stackID] = { [weak self] in
                    guard let _ = self else { return }
                    await LiveActivityManager.startOrUpdateIfNeeded(forStackID: stackID)
                }
            }
            // We don't run immediately here; we wait for lock/background or a manual kick.
        }
    }

    /// Supports calls that pass `stackID` first.
    func enqueue(stackID: String, reason: String) {
        enqueue(reason: reason, stackID: stackID)
    }

    // MARK: - Static conveniences (cover other call-site styles)

    static func enqueue(reason: String = "visibility", stackID: String) {
        shared.enqueue(reason: reason, stackID: stackID)
    }

    static func enqueue(stackID: String) {
        shared.enqueue(reason: "visibility", stackID: stackID)
    }

    static func enqueue(stackID: String, reason: String) {
        shared.enqueue(stackID: stackID, reason: reason)
    }

    // MARK: - New: Foreground deferral helper for brand-new starts

    /// If we’re in the foreground and close to the fire time, **queue** the start until first lock/background.
    /// Otherwise, execute immediately.
    @MainActor
    func maybeDeferOrRun(
        stackID: String,
        nextFire: Date,
        execute: @escaping () async -> Void
    ) async {
        let lead = nextFire.timeIntervalSinceNow
        let state = UIApplication.shared.applicationState

        if state == .active, lead <= deferThreshold {
            // Coalesce: one runnable per stack.
            pending[stackID] = execute
            MiniDiag.log("[ACT] defer.queue stack=\(stackID) lead=\(Int(lead))s state=active")
        } else {
            await execute()
        }
    }

    /// Manual kick (rarely needed; observers normally kick for us)
    func kick(_ reason: String = "manual") {
        Task { @MainActor in
            await self.drain(reason: reason)
        }
    }

    // MARK: - Internals (MainActor)

    @MainActor
    private var observersInstalled = false

    /// Coalesced pending attempts keyed by stackID.
    @MainActor
    private var pending: [String: () async -> Void] = [:]

    @MainActor
    private var tokens: [NSObjectProtocol] = []

    @MainActor
    private func installObserversIfNeeded() {
        guard observersInstalled == false else { return }
        observersInstalled = true

        let nc = NotificationCenter.default

        let t1 = nc.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.drain(reason: "willResignActive")
            }
        }

        let t2 = nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.drain(reason: "didEnterBackground")
            }
        }

        tokens.append(contentsOf: [t1, t2])
    }

    /// Run and clear all queued attempts.
    @MainActor
    private func drain(reason: String) async {
        guard pending.isEmpty == false else {
            MiniDiag.log("[ACT] defer.kick \(reason) (empty)")
            return
        }

        // Snapshot then clear to avoid re-entrancy issues if execute() re-queues.
        let runnables = pending
        pending.removeAll()
        MiniDiag.log("[ACT] defer.kick \(reason) queued=\(runnables.count)")

        for (stackID, op) in runnables {
            MiniDiag.log("[ACT] defer.run stack=\(stackID)")
            await op()
        }
    }
}
