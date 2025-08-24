//
//  LiveActivityManager+Prearm.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation
import ActivityKit
import os

/// iOS 16.2+
/// Coalesced, throttled pre-arm for Live Activities so we don't hit ActivityKit rate limits.
extension LiveActivityManager {

    private static let _log = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "LA.Prearm")

    // One plan (Task) per stackID, so reschedules replace older plans.
    private static var _plans = [String: Task<Void, Never>]()
    private static let _gate = LAStartGate()

    public struct LAStartPayload: Sendable {
        public let stackID: String
        public let stackName: String
        public let stepTitle: String
        public let ends: Date
        public let allowSnooze: Bool
        public let alarmID: String
        public let theme: ThemePayload
        public init(stackID: String, stackName: String, stepTitle: String, ends: Date, allowSnooze: Bool, alarmID: String, theme: ThemePayload) {
            self.stackID = stackID
            self.stackName = stackName
            self.stepTitle = stepTitle
            self.ends = ends
            self.allowSnooze = allowSnooze
            self.alarmID = alarmID
            self.theme = theme
        }
    }

    private static var _latestPayload = [String: LAStartPayload]()

    /// Record the latest state that should be shown when we prearm this stack's LA.
    public static func recordPrearmContext(_ payload: LAStartPayload) {
        _latestPayload[payload.stackID] = payload
    }

    /// Cancel any pending prearm plan for this stack.
    static func cancelPrearm(for stackID: String) {
        if let t = _plans.removeValue(forKey: stackID) { t.cancel() }
    }

    /// Plan a few **throttled** start attempts so the LA is reliably up before `effTarget`.
    /// Safe to call repeatedly — replaces any existing plan for this stack.
    @MainActor
    static func prearmIfNeeded(stackID: String, effTarget: Date, calendar: Calendar = .current) async {
        guard effTarget.timeIntervalSinceNow > 1 else { return } // already due

        // Replace any prior plan for this stack.
        cancelPrearm(for: stackID)

        // Local kill-switch
        if LAFlags.deviceDisabled {
            DiagLog.log("[LA] prearm.skip (device disabled) stack=\(stackID)")
            return
        }

        // OS-wide LA disabled?
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            _log.warning("Activities disabled; cannot prearm for stack=\(stackID, privacy: .public)")
            return
        }

        // Use the planner (e.g. [120, 90, 60, 48]s) and filter to the future.
        let now = Date()
        let planTimes = LiveActivityPlanner.plannedAttempts(for: effTarget, now: now)

        if planTimes.isEmpty {
            // Missed windows — a single opportunistic attempt (will self-guard).
            await attemptStartNow(stackID: stackID, effTarget: effTarget)
            return
        }

        DiagLog.log("[LA] prearm plan stack=\(stackID) effTarget=\(DiagLog.f(effTarget)) attempts=\(planTimes.map { Int($0.timeIntervalSinceNow) })s")

        // Background runner: sleep until each slot then do a gated start attempt.
        let task = Task.detached(priority: .background) {
            for t in planTimes {
                if Task.isCancelled { break }
                let wait = max(0, t.timeIntervalSinceNow)
                do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                catch { break } // cancelled
                if Task.isCancelled { break }
                await attemptStartNow(stackID: stackID, effTarget: effTarget)
            }
        }

        _plans[stackID] = task
    }

    /// Single, gated `start` attempt; does nothing if throttled/disabled/too late.
    @MainActor
    private static func attemptStartNow(stackID: String, effTarget: Date) async {
        if LAFlags.deviceDisabled {
            DiagLog.log("[LA] prearm.attempt.skip (device disabled) stack=\(stackID)")
            return
        }

        let remain = effTarget.timeIntervalSinceNow
        // Respect the planner’s hard floor (OS late-start guardrails)
        if remain < LiveActivityPlanner.hardMinimumLeadSeconds {
            DiagLog.log(String(format: "[LA] prearm.create.skip (too close; remain=%.0fs) stack=%@", remain, stackID))
            return
        }

        let ok = await _gate.shouldAttempt(now: Date())
        if ok == false {
            DiagLog.log("[LA] prearm (throttled) stack=\(stackID)")
            return
        }

        DiagLog.log(String(format: "[LA] prearm attempt stack=%@ remain=%.0fs", stackID, remain))

        guard let p = _latestPayload[stackID] else {
            DiagLog.log("[LA] prearm.attempt.skip (no payload) stack=\(stackID)")
            return
        }

        // Ask the controller to prearm/update. It knows how to classify errors.
        await LiveActivityController.shared.prearmOrUpdate(
            stackID: p.stackID,
            stackName: p.stackName,
            stepTitle: p.stepTitle,
            ends: p.ends,
            allowSnooze: p.allowSnooze,
            alarmID: p.alarmID,
            theme: p.theme
        )
    }
}

/// Global gate so we never spam ActivityKit.
private actor LAStartGate {
    // No more than `maxAttempts` within `windowLength`.
    private let windowLength: TimeInterval = 120   // 2 minutes
    private let maxAttempts: Int = 3               // across all stacks
    private var windowStart: Date = .distantPast
    private var attemptsInWindow: Int = 0
    private var lastAttemptAt: Date = .distantPast

    // Also add a tiny per-attempt cooldown so we never call twice within a few seconds.
    private let minSpacing: TimeInterval = 5

    func shouldAttempt(now: Date) -> Bool {
        if now.timeIntervalSince(lastAttemptAt) < minSpacing { return false }

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
