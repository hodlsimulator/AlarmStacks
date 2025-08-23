//
//  LiveActivityVisibilityRetry.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
import ActivityKit
import UIKit

/// Deprecated queue/observer-based retry. On iOS 26 we rely on `LiveActivityManager.sync`'s
/// own fast 5s retry window. We keep this type for source-compatibility, but it now
/// just forwards to `sync(…, reason: "visibility.retry")` immediately.
final class LiveActivityVisibilityRetry {

    static let shared = LiveActivityVisibilityRetry()
    private init() {}

    // MARK: - Public API

    func enqueue(reason: String = "visibility", stackID: String) {
        MiniDiag.log("[ACT] LA request failed (\(reason)); forwarding→sync stack=\(stackID)")
        Task { @MainActor in
            await LiveActivityManager.shared.sync(stackID: stackID, reason: "visibility.retry")
        }
    }

    func enqueue(stackID: String, reason: String) {
        enqueue(reason: reason, stackID: stackID)
    }

    // MARK: - Static conveniences (kept for call-site compatibility)

    static func enqueue(reason: String = "visibility", stackID: String) {
        shared.enqueue(reason: reason, stackID: stackID)
    }

    static func enqueue(stackID: String) {
        shared.enqueue(reason: "visibility", stackID: stackID)
    }

    static func enqueue(stackID: String, reason: String) {
        shared.enqueue(stackID: stackID, reason: reason)
    }

    // MARK: - Foreground deferral helper (now passthrough)

    /// Formerly deferred starts when the app was active and near fire time.
    /// Now: always executes immediately and lets `sync` handle visibility/rate limits.
    @MainActor
    func maybeDeferOrRun(
        stackID: String,
        nextFire: Date,
        execute: @escaping () async -> Void
    ) async {
        MiniDiag.log("[ACT] defer.skip (passthrough) stack=\(stackID) remain=~\(Int(nextFire.timeIntervalSinceNow))s")
        await execute()
    }

    /// No-op kick; retained for compatibility with older call sites.
    func kick(_ reason: String = "manual") {
        MiniDiag.log("[ACT] defer.kick \(reason) (noop)")
    }
}
