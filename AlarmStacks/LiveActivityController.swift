//
//  LiveActivityController.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
import ActivityKit
import SwiftUI

fileprivate let EARLIEST_REQUEST_LEAD: TimeInterval = 70   // request no earlier than ~T–70
fileprivate let LATE_START_FLOOR:      TimeInterval = 48   // avoid OS late-start guard

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    // MARK: - End all LAs (including probe) — async
    func endAll() async {
        for a in Activity<AlarmActivityAttributes>.activities {
            let content = ActivityContent(state: a.content.state, staleDate: nil)
            await a.end(content, dismissalPolicy: .immediate)
        }
        for p in Activity<ASProbeAttributes>.activities {
            let content = ActivityContent(state: p.content.state, staleDate: nil)
            await p.end(content, dismissalPolicy: .immediate)
        }
        DiagLog.log("[ACT] endAll()")
    }

    // MARK: - End a specific stack's LA — async
    func end(stackID: String) async {
        guard let act = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) else {
            DiagLog.log("[ACT] end: no activity for stack=\(stackID); ignoring")
            return
        }
        let content = ActivityContent(state: act.content.state, staleDate: nil)
        await act.end(content, dismissalPolicy: .immediate)
        DiagLog.log("[ACT] end stack=\(stackID)")
    }

    func end(for stackID: String) async { await end(stackID: stackID) }

    // MARK: - Start-or-update used by diagnostics & prearm paths

    func prearmOrUpdate(
        stackID: String,
        content st: AlarmActivityAttributes.ContentState
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            DiagLog.log("[ACT] prearmOrUpdate: activities disabled; stack=\(stackID)")
            return
        }
        if LAFlags.deviceDisabled {
            DiagLog.log("[LA] prearm.skip (device disabled) stack=\(stackID)")
            return
        }
        if LACap.inCooldown {
            DiagLog.log("[ACT] prearm.skip (cooldown) stack=\(stackID)")
            return
        }

        // Update if present (safe in bg/locked)
        if let existing = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) {
            let content = ActivityContent(state: st, staleDate: st.ends.addingTimeInterval(120))
            await existing.update(content)
            LADiag.logAuthAndActive(from: "prearm.update", stackID: stackID, expectingAlarmID: st.alarmID)
            LADiag.logTimer(whereFrom: "update", start: nil, end: st.ends)
            return
        }

        // Start new: only when eligible (fg + unlocked + enabled)
        guard LiveActivityManager.shouldAttemptRequestsNow() else {
            DiagLog.log("[ACT] prearm.skip not-eligible (fg+unlock+enabled=false) stack=\(stackID)")
            return
        }

        // Don’t ask too early; don’t ask too late (no existing)
        let lead = st.ends.timeIntervalSinceNow
        if lead > EARLIEST_REQUEST_LEAD {
            DiagLog.log("[ACT] prearm.skip too-early lead=\(Int(lead))s stack=\(stackID)")
            return
        }
        if lead < LATE_START_FLOOR {
            DiagLog.log("[ACT] prearm.skip late-window lead=\(Int(lead))s stack=\(stackID)")
            return
        }

        // Clear lingering activities (app + probes) to avoid caps.
        await hardResetActivities(reason: "prearm.start")

        let attrs = AlarmActivityAttributes(stackID: stackID)
        let content = ActivityContent(state: st, staleDate: st.ends.addingTimeInterval(120))

        func isCapError(_ e: Error) -> Bool {
            let s = String(describing: e).lowercased()
            return s.contains("targetmaximumexceeded") || s.contains("maximum number of activities")
        }

        do {
            _ = try Activity<AlarmActivityAttributes>.request(attributes: attrs, content: content, pushType: nil)
            LADiag.logAuthAndActive(from: "prearm.request", stackID: stackID, expectingAlarmID: st.alarmID)
            LADiag.logTimer(whereFrom: "start", start: nil, end: st.ends)
        } catch {
            let msg = "\(error)"
            DiagLog.log("[ACT] prearm.request FAILED stack=\(stackID) error=\(msg)")
            LADiag.logAuthAndActive(from: "prearm.request.fail", stackID: stackID, expectingAlarmID: st.alarmID)
            if isCapError(error) {
                // Short backoff; manager/app-life hooks will retry when eligible.
                LACap.enterCooldown(seconds: 20, reason: "targetMaximumExceeded")
                return
            }
        }
    }

    func prearmOrUpdate(
        stackID: String,
        stackName: String,
        stepTitle: String,
        ends: Date,
        allowSnooze: Bool,
        alarmID: String,
        theme: ThemePayload
    ) async {
        let st = AlarmActivityAttributes.ContentState(
            stackName: stackName,
            stepTitle: stepTitle,
            ends: ends,
            allowSnooze: allowSnooze,
            alarmID: alarmID,
            firedAt: nil,
            theme: theme
        )
        await prearmOrUpdate(stackID: stackID, content: st)
    }

    // MARK: - Mark an alarm as fired

    func markFired(stackID: String, alarmID: String, ends: Date) async {
        await _markFiredCommon(stackID: stackID, alarmID: alarmID, ends: ends)
    }
    func markFired(stackID: String, id: String, ends: Date) async {
        await _markFiredCommon(stackID: stackID, alarmID: id, ends: ends)
    }
    func markFired(stackID: String, alarmID: String) async {
        if let act = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) {
            await _markFiredCommon(stackID: stackID, alarmID: alarmID, ends: act.content.state.ends)
        } else {
            DiagLog.log("[ACT] markFired(stackID:alarmID:) no activity; ignoring")
        }
    }
    func markFired(stackID: String, id: String) async { await markFired(stackID: stackID, alarmID: id) }

    func markFired(stackID: String) async {
        guard let act = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) else {
            DiagLog.log("[ACT] markFired: no activity for stack=\(stackID); ignoring")
            return
        }
        await _markFiredCommon(stackID: stackID, alarmID: act.content.state.alarmID, ends: act.content.state.ends)
    }
    func markFired(for stackID: String, id: String) async { await markFired(stackID: stackID, alarmID: id) }

    private func _markFiredCommon(stackID: String, alarmID: String, ends: Date) async {
        guard let act = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) else {
            DiagLog.log("[ACT] markFiredNow() no active activities; ignoring")
            return
        }
        var st = act.content.state
        st.firedAt = Date()
        st.ends = ends
        let content = ActivityContent(state: st, staleDate: st.ends.addingTimeInterval(120))
        await act.update(content)
        DiagLog.log("[ACT] markFiredNow stack=\(stackID) step=\(st.stepTitle) firedAt=\(DiagLog.f(st.firedAt ?? Date())) ends=\(DiagLog.f(ends)) id=\(alarmID)")
        LADiag.logAuthAndActive(from: "markFiredNow", stackID: stackID, expectingAlarmID: alarmID)
        LADiag.logTimer(whereFrom: "markFiredNow", start: st.firedAt, end: st.ends)
    }

    // MARK: - Debug starter (auto-waits to safe window)

    func startDebug(
        stackID: String = "DEBUG-STACK",
        stackName: String = "Debug",
        stepTitle: String = "Debug Step",
        seconds: Int = 90,
        allowSnooze: Bool = false
    ) {
        let ends = Date().addingTimeInterval(TimeInterval(seconds))
        let st = AlarmActivityAttributes.ContentState(
            stackName: stackName,
            stepTitle: stepTitle,
            ends: ends,
            allowSnooze: allowSnooze,
            alarmID: "debug-\(UUID().uuidString)",
            firedAt: nil,
            theme: ThemeMap.payload(for: "Default")
        )

        Task { @MainActor in
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                DiagLog.log("[ACT] debug.start: activities disabled")
                return
            }
            if LAFlags.deviceDisabled {
                DiagLog.log("[ACT] debug.start: device disabled; skipping")
                return
            }

            // If too early, wait until we reach the safe window (keeping UI in foreground).
            var wait: TimeInterval = 0
            let lead = ends.timeIntervalSinceNow
            if lead > EARLIEST_REQUEST_LEAD {
                wait = lead - EARLIEST_REQUEST_LEAD + 0.5
                DiagLog.log("[ACT] debug.start: waiting \(Int(wait))s to safe window")
            }
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }

            // Recheck eligibility and late floor
            guard LiveActivityManager.shouldAttemptRequestsNow() else {
                DiagLog.log("[ACT] debug.start: not-eligible at attempt (fg+unlock+enabled=false)")
                return
            }
            if ends.timeIntervalSinceNow < LATE_START_FLOOR {
                DiagLog.log("[ACT] debug.start: late-window lead=\(Int(ends.timeIntervalSinceNow))s")
                return
            }

            // Clear any lingering activities that could trip caps
            await hardResetActivities(reason: "debug.start")

            let attrs = AlarmActivityAttributes(stackID: stackID)
            let content = ActivityContent(state: st, staleDate: ends.addingTimeInterval(120))

            func isCapError(_ e: Error) -> Bool {
                let s = String(describing: e).lowercased()
                return s.contains("targetmaximumexceeded") || s.contains("maximum number of activities")
            }

            do {
                _ = try Activity<AlarmActivityAttributes>.request(attributes: attrs, content: content, pushType: nil)
                LADiag.logAuthAndActive(from: "debug.start", stackID: stackID, expectingAlarmID: st.alarmID)
                LADiag.logTimer(whereFrom: "start", start: nil, end: ends)
            } catch {
                DiagLog.log("[ACT] debug.request FAILED stack=\(stackID) error=\(error)")
                if isCapError(error) {
                    LACap.enterCooldown(seconds: 20, reason: "targetMaximumExceeded")
                }
            }
        }
    }

    @MainActor
    private func hardResetActivities(reason: String) async {
        for a in Activity<AlarmActivityAttributes>.activities {
            let content = ActivityContent(state: a.content.state, staleDate: nil)
            await a.end(content, dismissalPolicy: .immediate)
        }
        for p in Activity<ASProbeAttributes>.activities {
            let content = ActivityContent(state: p.content.state, staleDate: nil)
            await p.end(content, dismissalPolicy: .immediate)
        }
        DiagLog.log("[ACT] hardResetActivities reason=\(reason)")
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
    }
}
