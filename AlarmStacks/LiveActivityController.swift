//
//  LiveActivityController.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
import ActivityKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    // MARK: - Gating

    private func shouldAttemptRequestsNow() -> Bool {
        if !ActivityAuthorizationInfo().areActivitiesEnabled {
            DiagLog.log("[ACT] gate: activities disabled by user")
            return false
        }
        if LAFlags.deviceDisabled {
            DiagLog.log("[ACT] gate: device disabled (LAFlags)")
            return false
        }
        if LACap.inCooldown {
            DiagLog.log("[ACT] gate: cooldown active")
            return false
        }
        #if canImport(UIKit)
        guard UIApplication.shared.isProtectedDataAvailable else {
            DiagLog.log("[ACT] gate: protected data unavailable (locked)")
            return false
        }
        let state = UIApplication.shared.applicationState
        if !(state == .active || state == .inactive) {
            DiagLog.log("[ACT] gate: app not visible enough (state=\(state.rawValue))")
            return false
        }
        #endif
        return true
    }

    // MARK: - AK/AppGroup mirrors to keep refreshers happy

    /// Some refresh paths rebuild the LA by scanning AK keys in UserDefaults.
    /// If those keys aren’t there yet, they’ll wrongly conclude “no future”
    /// and end the activity. We mirror a minimal, single-candidate view here.
    private func mirrorAKStore(for stackID: String, state st: AlarmActivityAttributes.ContentState) {
        let ud = UserDefaults.standard

        // Use the provided alarmID if present; fall back to a stable-ish token
        // so we don’t spam the list with new UUIDs if a caller forgot to pass one.
        let alarmID = st.alarmID.isEmpty ? "la-\(stackID)" : st.alarmID

        // 1) ids list — write both historical key shapes to be safe.
        func mergeIDs(_ key: String) {
            var ids = Set(ud.stringArray(forKey: key) ?? [])
            ids.insert(alarmID)
            ud.set(Array(ids), forKey: key)
        }
        mergeIDs("alarmkit.ids.\(stackID)")
        mergeIDs("ak.ids.\(stackID)")

        // 2) anchor and per-id fields expected by the refresh scanner.
        ud.set(st.ends.timeIntervalSince1970, forKey: "ak.firstTarget.\(stackID)")
        ud.set(st.stackName,                     forKey: "ak.stackName.\(alarmID)")
        ud.set(st.stepTitle,                     forKey: "ak.stepTitle.\(alarmID)")
        ud.set(st.allowSnooze,                   forKey: "ak.allowSnooze.\(alarmID)")
        ud.set(st.ends.timeIntervalSince1970,    forKey: "ak.effTarget.\(alarmID)")
        ud.set(st.ends.timeIntervalSince1970,    forKey: "ak.expected.\(alarmID)")
        ud.set(0.0,                              forKey: "ak.offsetFromFirst.\(alarmID)")

        // Also keep the static widget bridge updated.
        NextAlarmBridge.write(.init(stackName: st.stackName, stepTitle: st.stepTitle, fireDate: st.ends))
    }

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

    // Compatibility wrapper
    func end(for stackID: String) async { await end(stackID: stackID) }

    // MARK: - Start-or-update used by diagnostics & prearm paths

    /// Update an existing Live Activity for this stackID, or start a new one if none exists.
    func prearmOrUpdate(
        stackID: String,
        content st: AlarmActivityAttributes.ContentState
    ) async {
        guard shouldAttemptRequestsNow() else {
            DiagLog.log("[ACT] prearm.skip (gate) stack=\(stackID)")
            return
        }

        // Mirror AK/AppGroup immediately so any concurrent refresh doesn’t kill us.
        mirrorAKStore(for: stackID, state: st)

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

        // Start new if not present — request directly (single-shot)
        let attrs = AlarmActivityAttributes(stackID: stackID)
        let content = ActivityContent(
            state: st,
            staleDate: st.ends.addingTimeInterval(120)
        )

        func isCapError(_ e: Error) -> Bool {
            let s = String(describing: e).lowercased()
            return s.contains("targetmaximumexceeded") || s.contains("maximum number of activities")
        }

        do {
            _ = try Activity<AlarmActivityAttributes>.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
            // Mirror again after success (harmless; keeps data fresh if ends changed).
            mirrorAKStore(for: stackID, state: st)
            LADiag.logAuthAndActive(from: "prearm.request", stackID: stackID, expectingAlarmID: st.alarmID)
            LADiag.logTimer(whereFrom: "start", start: nil, end: st.ends)
        } catch {
            let msg = "\(error)"
            DiagLog.log("[ACT] prearm.request FAILED stack=\(stackID) error=\(msg)")
            LADiag.logAuthAndActive(from: "prearm.request.fail", stackID: stackID, expectingAlarmID: st.alarmID)

            if isCapError(error) {
                await hardResetActivities(reason: "cap.prearm")
                LACap.enterCooldown(seconds: 90, reason: "targetMaximumExceeded")

                // Try once more if we still have safe lead
                if st.ends.timeIntervalSinceNow > 52, shouldAttemptRequestsNow() {
                    do {
                        _ = try Activity<AlarmActivityAttributes>.request(
                            attributes: attrs,
                            content: content,
                            pushType: nil
                        )
                        mirrorAKStore(for: stackID, state: st)
                        LADiag.logAuthAndActive(from: "prearm.request.retry.ok", stackID: stackID, expectingAlarmID: st.alarmID)
                        LADiag.logTimer(whereFrom: "retry.start", start: nil, end: st.ends)
                    } catch {
                        DiagLog.log("[ACT] prearm.request.retry FAILED stack=\(stackID) error=\(error)")
                    }
                }
            }
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

    // MARK: - Fired state

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
        st.ends = ends // refresh target if supplied

        // Keep AK mirror in sync so refreshers don’t flip back to “next step”.
        mirrorAKStore(for: stackID, state: st)

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
            guard shouldAttemptRequestsNow() else {
                DiagLog.log("[ACT] debug.start: gate blocked")
                return
            }

            // Clear any lingering activities that could trip caps (app + probes)
            await hardResetActivities(reason: "debug.start")

            func isCapError(_ e: Error) -> Bool {
                let s = String(describing: e).lowercased()
                return s.contains("targetmaximumexceeded") || s.contains("maximum number of activities")
            }

            do {
                _ = try Activity<AlarmActivityAttributes>.request(
                    attributes: attrs,
                    content: content,
                    pushType: nil
                )
                // Mirror so refreshers won’t kill the debug LA either.
                mirrorAKStore(for: stackID, state: st)
                LADiag.logAuthAndActive(from: "debug.start", stackID: stackID, expectingAlarmID: st.alarmID)
                LADiag.logTimer(whereFrom: "start", start: nil, end: ends)
            } catch {
                let msg = "\(error)"
                DiagLog.log("[ACT] prearm.request FAILED stack=\(stackID) error=\(msg)")
                LADiag.logAuthAndActive(from: "prearm.request.fail", stackID: stackID, expectingAlarmID: st.alarmID)

                if isCapError(error) {
                    await hardResetActivities(reason: "cap.prearm")
                    LACap.enterCooldown(seconds: 90, reason: "targetMaximumExceeded")

                    // single retry if there's still safe lead
                    if ends.timeIntervalSinceNow > 52, shouldAttemptRequestsNow() {
                        do {
                            _ = try Activity<AlarmActivityAttributes>.request(
                                attributes: AlarmActivityAttributes(stackID: stackID),
                                content: content,
                                pushType: nil
                            )
                            mirrorAKStore(for: stackID, state: st)
                            LADiag.logAuthAndActive(from: "prearm.request.retry.ok", stackID: stackID, expectingAlarmID: st.alarmID)
                            LADiag.logTimer(whereFrom: "retry.start", start: nil, end: ends)
                            return
                        } catch {
                            DiagLog.log("[ACT] prearm.request.retry FAILED stack=\(stackID) error=\(error)")
                        }
                    }
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
