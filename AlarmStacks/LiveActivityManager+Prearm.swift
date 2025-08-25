//
//  LiveActivityManager+Prearm.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation
import ActivityKit
import os

/// iOS 16.2+ (project targets iOS 16)
/// Coalesced, throttled pre-arm for Live Activities.
/// Modified to: no visibility gate, no “too close” hard floor, and
/// to persist minimal context so `refreshFromGroup` can build the LA.
@MainActor
extension LiveActivityManager {

    private static let _log = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "LA.Prearm")

    // One plan (Task) per stackID, so reschedules replace older plans.
    private static var _plans = [String: Task<Void, Never>]()

    public struct LAStartPayload: Sendable {
        public let stackID: String
        public let stackName: String
        public let stepTitle: String
        public let ends: Date
        public let allowSnooze: Bool
        public let alarmID: String
        public let theme: ThemePayload
        public init(stackID: String,
                    stackName: String,
                    stepTitle: String,
                    ends: Date,
                    allowSnooze: Bool,
                    alarmID: String,
                    theme: ThemePayload) {
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

    // Local key helpers (mirror of those used by Start.swift; duplicated here because that enum is file-private there).
    private enum K {
        static func idsKey(_ stackID: String) -> String { "alarmkit.ids.\(stackID)" }
        static func stackNameKey(_ id: UUID) -> String { "ak.stackName.\(id.uuidString)" }
        static func stepTitleKey(_ id: UUID) -> String { "ak.stepTitle.\(id.uuidString)" }
        static func allowSnoozeKey(_ id: UUID) -> String { "ak.allowSnooze.\(id.uuidString)" }
        static func effTargetKey(_ id: UUID) -> String { "ak.effTarget.\(id.uuidString)" }
        static func firstTargetKey(_ stackID: String) -> String { "ak.firstTarget.\(stackID)" }
    }

    /// Record the latest state that should be shown when we prearm this stack's LA.
    /// Also writes the minimal fields to defaults so `refreshFromGroup` can operate.
    public static func recordPrearmContext(_ payload: LAStartPayload) {
        _latestPayload[payload.stackID] = payload

        guard let alarmUUID = UUID(uuidString: payload.alarmID) else {
            DiagLog.log("[LA] prearm.record skip (bad alarmID) stack=\(payload.stackID)")
            return
        }

        let std = UserDefaults.standard
        let grp = UserDefaults(suiteName: AppGroups.main)

        // Ensure the per-stack ID list contains this alarm id.
        func appendID(_ ud: UserDefaults?) {
            guard let ud else { return }
            var arr = ud.stringArray(forKey: K.idsKey(payload.stackID)) ?? []
            if arr.contains(alarmUUID.uuidString) == false {
                arr.append(alarmUUID.uuidString)
                ud.set(arr, forKey: K.idsKey(payload.stackID))
            }
        }
        appendID(std)
        appendID(grp)

        // Per-alarm fields read by Start pass.
        std.set(payload.stackName,                   forKey: K.stackNameKey(alarmUUID))
        std.set(payload.stepTitle,                   forKey: K.stepTitleKey(alarmUUID))
        std.set(payload.allowSnooze,                 forKey: K.allowSnoozeKey(alarmUUID))
        std.set(payload.ends.timeIntervalSince1970,  forKey: K.effTargetKey(alarmUUID))

        grp?.set(payload.stackName,                  forKey: K.stackNameKey(alarmUUID))
        grp?.set(payload.stepTitle,                  forKey: K.stepTitleKey(alarmUUID))
        grp?.set(payload.allowSnooze,                forKey: K.allowSnoozeKey(alarmUUID))
        grp?.set(payload.ends.timeIntervalSince1970, forKey: K.effTargetKey(alarmUUID))

        // First target (for relative-step fallback) — only set if not present.
        let firstKey = K.firstTargetKey(payload.stackID)
        if std.object(forKey: firstKey) == nil {
            std.set(payload.ends.timeIntervalSince1970, forKey: firstKey)
        }
        if grp?.object(forKey: firstKey) == nil {
            grp?.set(payload.ends.timeIntervalSince1970, forKey: firstKey)
        }

        LADiag.logAuthAndActive(from: "recordPrearm", stackID: payload.stackID, expectingAlarmID: payload.alarmID)
    }

    /// Cancel any pending prearm plan for this stack.
    static func cancelPrearm(for stackID: String) {
        if let t = _plans.removeValue(forKey: stackID) { t.cancel() }
    }

    /// Plan a few **throttled** start attempts so the LA is reliably up before `effTarget`.
    /// Safe to call repeatedly — replaces any existing plan for this stack.
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

        // Use the planner (e.g. [120, 90, 60, 48]s) — already filtered to the future by planner.
        let now = Date()
        let planTimes = LiveActivityPlanner.plannedAttempts(for: effTarget, now: now)

        // Try once immediately so the tile can appear right after setting the time,
        // even if effTarget is far in the future. Later retries will coalesce and update.
        await _attemptStartUsingPayload(stackID: stackID, effTarget: effTarget)

        if planTimes.isEmpty {
            // No future slots — we've already attempted once above.
            return
        }

        DiagLog.log("[LA] prearm plan stack=\(stackID) effTarget=\(DiagLog.f(effTarget)) attempts=\(planTimes.map { Int($0.timeIntervalSinceNow) })s")
        LADiag.logTimer(whereFrom: "prearm.schedule", start: nil, end: effTarget, now: now)

        // Background runner: sleep until each slot then do an ungated start attempt.
        let task = Task.detached(priority: .background) {
            for t in planTimes {
                if Task.isCancelled { break }
                let wait = max(0, t.timeIntervalSinceNow)
                do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                catch { break } // cancelled
                if Task.isCancelled { break }
                await _attemptStartUsingPayload(stackID: stackID, effTarget: effTarget)
            }
        }

        _plans[stackID] = task
    }

    /// Single, ungated `start` attempt using the most recent payload.
    /// (Renamed to avoid clashing with the public shim in AttemptStartNowShims.)
    private static func _attemptStartUsingPayload(stackID: String, effTarget: Date) async {
        guard let p = _latestPayload[stackID] else {
            DiagLog.log("[LA] prearm.attempt.skip (no payload) stack=\(stackID)")
            return
        }

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
