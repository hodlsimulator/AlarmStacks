//
//  LiveActivityManager+Prearm.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation
import ActivityKit
import OSLog
#if canImport(UIKit)
import UIKit
#endif

@MainActor
extension LiveActivityManager {
    // iOS 26+ only in this project.
    private static let prearmHorizon: TimeInterval = 3 * 60 * 60 // 3h
    private static var cooldownUntil = Date.distantPast
    private static var pending: [String: Date] = [:] // stackID -> effTarget
    private static let logger = Logger(subsystem: "com.hodlsimulator.alarmstacks",
                                       category: "LiveActivity.Prearm")

    /// Pre-arm a Live Activity for this stack (only when app is foreground).
    /// We deliberately delegate to your existing `start(stackID:calendar:)`
    /// so we don’t need to construct attributes/content state here.
    static func ensurePrearmed(stackID: String, effTarget: Date) {
        // Only bother when the next fire is reasonably soon.
        guard effTarget.timeIntervalSinceNow <= prearmHorizon else { return }

        #if canImport(UIKit)
        guard UIApplication.shared.applicationState == .active else {
            pending[stackID] = effTarget
            return
        }
        #endif

        guard Date() >= cooldownUntil else {
            pending[stackID] = effTarget
            return
        }

        // If an activity for this stack already exists, your `start(...)`
        // implementation will reuse/update it. If not, it will request one.
        // (This avoids any mismatched ContentState initializers.)
        Self.start(stackID: stackID, calendar: .current)
    }

    /// Run any queued prearm attempts once we become active.
    static func drainForegroundQueue() {
        #if canImport(UIKit)
        guard UIApplication.shared.applicationState == .active else { return }
        #endif
        let work = pending
        pending.removeAll()
        for (sid, when) in work {
            ensurePrearmed(stackID: sid, effTarget: when)
        }
    }

    /// Optional: call this from your own LA error paths to avoid tight loops.
    static func applyCooldown(seconds: TimeInterval = 20) {
        cooldownUntil = Date().addingTimeInterval(seconds)
        logger.debug("Applied LA cooldown for \(seconds, privacy: .public)s")
    }
}
