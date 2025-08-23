//
//  LiveActivityManager+Prearm.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation
import ActivityKit
import os

/// iOS 26+
/// Coalesced, throttled pre-arm for Live Activities so we don't hit ActivityKit rate limits.
/// - Plans a small number of attempts at strategic offsets before `effTarget`
/// - Cancels any older plan for the same `stackID`
/// - Throttles globally to avoid rapid-fire `start` calls
extension LiveActivityManager {

    private static let _log = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "LA.Prearm")

    // One plan (Task) per stackID, so reschedules replace older plans.
    private static var _plans = [String: Task<Void, Never>]()
    private static let _gate = LAStartGate()

    /// Cancel any pending prearm plan for this stack.
    static func cancelPrearm(for stackID: String) {
        if let t = _plans.removeValue(forKey: stackID) { t.cancel() }
    }

    /// Plan a few **throttled** start attempts so the LA is reliably up before `effTarget`.
    /// Safe to call repeatedly — replaces any existing plan for this stack.
    @MainActor
    static func prearmIfNeeded(stackID: String, effTarget: Date, calendar: Calendar = .current) async {
        // Already due/late → nothing useful to prearm.
        guard effTarget.timeIntervalSinceNow > 1 else { return }

        // Replace any prior plan for this stack.
        cancelPrearm(for: stackID)

        // Local kill-switch for debugging.
        if LAFlags.deviceDisabled {
            DiagLog.log("[LA] prearm.skip (device disabled) stack=\(stackID)")
            return
        }

        // OS-wide LA disabled?
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            _log.warning("Activities disabled; cannot prearm for stack=\(stackID, privacy: .public)")
            return
        }

        // Fuse tripped? Skip scheduling any attempts.
        if isInCooldown {
            DiagLog.log("[LA] prearm.skip (cooldown) stack=\(stackID)")
            return
        }

        // Choose sparse offsets to avoid rate-limit: try at T-31s and T-11s.
        let offsets: [TimeInterval] = [31, 11]

        // Compute absolute attempt times, drop ones already in the past.
        let planTimes = offsets
            .map { effTarget.addingTimeInterval(-$0) }
            .filter { $0.timeIntervalSinceNow > 0.5 }

        if planTimes.isEmpty {
            // We missed our windows; do a single attempt now.
            if Task.isCancelled == false {
                await attemptStartNow(stackID: stackID, calendar: calendar, effTarget: effTarget)
            }
            return
        }

        DiagLog.log("[LA] prearm plan stack=\(stackID) effTarget=\(DiagLog.f(effTarget)) attempts=\(planTimes.map { Int($0.timeIntervalSinceNow) })s")

        // Background plan runner: sleep until each slot then do a gated start attempt.
        let task = Task.detached(priority: .background) {
            for t in planTimes {
                if Task.isCancelled { break }
                let wait = max(0, t.timeIntervalSinceNow)
                do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                catch { break } // cancelled
                if Task.isCancelled { break }
                await attemptStartNow(stackID: stackID, calendar: calendar, effTarget: effTarget)
            }
        }

        _plans[stackID] = task
    }

    /// Single, gated `start` attempt; does nothing if throttled/cooldown/disabled.
    @MainActor
    private static func attemptStartNow(stackID: String, calendar: Calendar, effTarget: Date) async {
        if LAFlags.deviceDisabled {
            DiagLog.log("[LA] prearm.attempt.skip (device disabled) stack=\(stackID)")
            return
        }
        if isInCooldown {
            DiagLog.log("[LA] prearm.attempt.skip (cooldown) stack=\(stackID)")
            return
        }

        let now = Date()
        let ok = await _gate.shouldAttempt(now: now)
        if ok == false {
            DiagLog.log("[LA] prearm (throttled) stack=\(stackID)")
            return
        }
        DiagLog.log(String(format: "[LA] prearm attempt stack=%@ remain=%.0fs",
                           stackID, effTarget.timeIntervalSinceNow))
        start(stackID: stackID, calendar: calendar)
    }
}

/// Global gate so we never spam ActivityKit.
private actor LAStartGate {
    // No more than `maxAttempts` within `windowLength`.
    private let windowLength: TimeInterval = 120   // 2 minutes
    private let maxAttempts: Int = 4               // across all stacks
    private var windowStart: Date = .distantPast
    private var attemptsInWindow: Int = 0
    private var lastAttemptAt: Date = .distantPast

    // Also add a tiny per-attempt cooldown so we never call twice within a few seconds.
    private let minSpacing: TimeInterval = 4

    func shouldAttempt(now: Date) -> Bool {
        // Per-attempt spacing
        if now.timeIntervalSince(lastAttemptAt) < minSpacing { return false }

        // Window accounting
        if now.timeIntervalSince(windowStart) > windowLength {
            windowStart = now
            attemptsInWindow = 0
        }
        if attemptsInWindow >= maxAttempts { return false }

        attemptsInWindow += 1
        lastAttemptAt = now
        return true
    }
}
