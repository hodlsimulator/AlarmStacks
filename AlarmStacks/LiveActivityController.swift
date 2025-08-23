//
//  LiveActivityController.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
import ActivityKit
import SwiftUI

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
        // End smoke-test probe activities (defined in DiagnosticsLog.swift)
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

    // ---- Compatibility wrapper for older call sites ----
    func end(for stackID: String) async { await end(stackID: stackID) }

    // MARK: - Start-or-update used by diagnostics & prearm paths

    /// Update an existing Live Activity for this stackID, or start a new one if none exists.
    func prearmOrUpdate(
        stackID: String,
        content st: AlarmActivityAttributes.ContentState
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            DiagLog.log("[ACT] prearmOrUpdate: activities disabled; stack=\(stackID)")
            return
        }

        // Local kill-switch
        if LAFlags.deviceDisabled {
            DiagLog.log("[LA] prearm.skip (device disabled) stack=\(stackID)")
            return
        }

        // Update if present
        if let existing = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) {
            let content = ActivityContent(
                state: st,
                staleDate: st.ends.addingTimeInterval(120)
            )
            await existing.update(content)
            LADiag.logAuthAndActive(from: "prearm.update", stackID: stackID, expectingAlarmID: st.alarmID)
            LADiag.logTimer(whereFrom: "update", start: nil, end: st.ends)
            return
        }

        // Start new if not present
        let attrs = AlarmActivityAttributes(stackID: stackID)
        let content = ActivityContent(
            state: st,
            staleDate: st.ends.addingTimeInterval(120)
        )
        do {
            _ = try await LiveActivityGuard.requestWithBestEffort(for: AlarmActivityAttributes.self, cap: 1) {
                try Activity<AlarmActivityAttributes>.request(
                    attributes: attrs,
                    content: content,
                    pushType: nil
                )
            }
            LADiag.logAuthAndActive(from: "prearm.request", stackID: stackID, expectingAlarmID: st.alarmID)
            LADiag.logTimer(whereFrom: "start", start: nil, end: st.ends)
        } catch {
            let msg = "\(error)"
            DiagLog.log("[ACT] prearm.request FAILED stack=\(stackID) error=\(msg)")
            LADiag.logAuthAndActive(from: "prearm.request.fail", stackID: stackID, expectingAlarmID: st.alarmID)
        }
    }

    /// Convenience overload when you don't want to construct ContentState at call site.
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

    // MARK: - Mark an alarm as fired (update firedAt; keep ends/timer target)

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

    func markFired(stackID: String, id: String) async {
        await markFired(stackID: stackID, alarmID: id)
    }

    func markFired(stackID: String) async {
        guard let act = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) else {
            DiagLog.log("[ACT] markFired: no activity for stack=\(stackID); ignoring")
            return
        }
        await _markFiredCommon(stackID: stackID, alarmID: act.content.state.alarmID, ends: act.content.state.ends)
    }

    func markFired(for stackID: String, id: String) async {
        await markFired(stackID: stackID, alarmID: id)
    }

    private func _markFiredCommon(stackID: String, alarmID: String, ends: Date) async {
        guard let act = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) else {
            DiagLog.log("[ACT] markFiredNow() no active activities; ignoring")
            return
        }
        var st = act.content.state
        st.firedAt = Date()
        st.ends = ends // refresh effective end if the caller supplies it
        let content = ActivityContent(state: st, staleDate: st.ends.addingTimeInterval(120))
        await act.update(content)
        DiagLog.log("[ACT] markFiredNow stack=\(stackID) step=\(st.stepTitle) firedAt=\(DiagLog.f(st.firedAt ?? Date())) ends=\(DiagLog.f(ends)) id=\(alarmID)")
        LADiag.logAuthAndActive(from: "markFiredNow", stackID: stackID, expectingAlarmID: alarmID)
        LADiag.logTimer(whereFrom: "markFiredNow", start: st.firedAt, end: st.ends)
    }

    // MARK: - Simple debug starter (used by the debug menu)
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

        let attrs = AlarmActivityAttributes(stackID: stackID)
        let content = ActivityContent(state: st, staleDate: ends.addingTimeInterval(120))

        Task { @MainActor in
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                DiagLog.log("[ACT] debug.start: activities disabled")
                return
            }
            if LAFlags.deviceDisabled {
                DiagLog.log("[ACT] debug.start: device disabled; skipping")
                return
            }
            do {
                _ = try await LiveActivityGuard.requestWithBestEffort(for: AlarmActivityAttributes.self, cap: 1) {
                    try Activity<AlarmActivityAttributes>.request(
                        attributes: attrs,
                        content: content,
                        pushType: nil
                    )
                }
                LADiag.logAuthAndActive(from: "debug.start", stackID: stackID, expectingAlarmID: st.alarmID)
                LADiag.logTimer(whereFrom: "start", start: nil, end: ends)
            } catch {
                DiagLog.log("[ACT] debug.start FAILED error=\(error)")
                LADiag.logAuthAndActive(from: "debug.start.fail", stackID: stackID, expectingAlarmID: st.alarmID)
            }
        }
    }
}
