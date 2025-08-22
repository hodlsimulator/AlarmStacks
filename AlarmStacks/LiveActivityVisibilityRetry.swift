//
//  LiveActivityVisibilityRetry.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// If an LA can't show due to a transient visibility condition,
/// we stash the stackID and retry as the app backgrounds/locks.
@MainActor
enum LiveActivityVisibilityRetry {
    private static var isInstalled = false
    private static var pending = Set<String>() // stackIDs
    #if canImport(UIKit)
    private static var tokens: [NSObjectProtocol] = []
    #endif

    static func registerPending(stackID: String) {
        pending.insert(stackID)
        installIfNeeded()
    }

    private static func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true
        #if canImport(UIKit)
        let nc = NotificationCenter.default

        // Fires when the user hits the lock button (before background).
        let t1 = nc.addObserver(forName: UIApplication.willResignActiveNotification,
                                object: nil, queue: .main) { _ in
            Task { @MainActor in
                drain(reason: "willResignActive")
            }
        }
        tokens.append(t1)

        // Fires after the app actually backgrounds (screen locked).
        let t2 = nc.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                object: nil, queue: .main) { _ in
            Task { @MainActor in
                // Try shortly after backgrounding, then again a bit later.
                try? await Task.sleep(nanoseconds: 250_000_000)
                drain(reason: "didEnterBackground")
                try? await Task.sleep(nanoseconds: 800_000_000)
                drain(reason: "didEnterBackground.late")
            }
        }
        tokens.append(t2)
        #endif
    }

    static func drain(reason: String) {
        guard !pending.isEmpty else { return }
        let ids = pending
        pending.removeAll()
        for id in ids {
            LiveActivityManager.start(stackID: id, reason: "visibilityRetry:\(reason)")
            // Force a content update even if nothing changed (nudges lock screen).
            Task { await LiveActivityManager.forceRefreshActiveActivities(forStackID: id) }
        }
    }

    #if canImport(UIKit)
    /// If we update while background/locked (e.g., moving to Step 2), nudge visibility.
    static func nudgeIfBackground(stackID: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            LiveActivityManager.start(stackID: stackID, reason: "visibilityNudge.quick")
            await LiveActivityManager.forceRefreshActiveActivities(forStackID: stackID)

            try? await Task.sleep(nanoseconds: 900_000_000)
            LiveActivityManager.start(stackID: stackID, reason: "visibilityNudge.late")
            await LiveActivityManager.forceRefreshActiveActivities(forStackID: stackID)
        }
    }
    #endif
}
