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

    // MARK: - Minimal gate (no visibility / no cooldown)

    private func shouldAttemptRequestsNow() -> Bool {
        if !ActivityAuthorizationInfo().areActivitiesEnabled {
            DiagLog.log("[ACT] gate: activities disabled by user/OS")
            return false
        }
        if LAFlags.deviceDisabled {
            DiagLog.log("[ACT] gate: device disabled (LAFlags)")
            return false
        }
        return true
    }

    // MARK: - AK/AppGroup mirror (Standard + App Group)

    private func mirrorAKStore(for stackID: String, state st: AlarmActivityAttributes.ContentState) {
        let alarmID = st.alarmID.isEmpty ? "la-\(stackID)" : st.alarmID

        let stores: [UserDefaults] = {
            var a: [UserDefaults] = [UserDefaults.standard]
            if let g = UserDefaults(suiteName: AppGroups.main) { a.append(g) }
            return a
        }()

        func mergeIDs(_ ud: UserDefaults, _ key: String) {
            var ids = Set(ud.stringArray(forKey: key) ?? [])
            ids.insert(alarmID)
            ud.set(Array(ids), forKey: key)
        }

        for ud in stores {
            mergeIDs(ud, "alarmkit.ids.\(stackID)")
            mergeIDs(ud, "ak.ids.\(stackID)")
            ud.set(st.ends.timeIntervalSince1970, forKey: "ak.firstTarget.\(stackID)")
            ud.set(st.stackName,                  forKey: "ak.stackName.\(alarmID)")
            ud.set(st.stepTitle,                  forKey: "ak.stepTitle.\(alarmID)")
            ud.set(st.allowSnooze,                forKey: "ak.allowSnooze.\(alarmID)")
            ud.set(st.ends.timeIntervalSince1970, forKey: "ak.effTarget.\(alarmID)")
            ud.set(st.ends.timeIntervalSince1970, forKey: "ak.expected.\(alarmID)")
            ud.set(0.0,                           forKey: "ak.offsetFromFirst.\(alarmID)")
        }

        NextAlarmBridge.write(.init(stackName: st.stackName, stepTitle: st.stepTitle, fireDate: st.ends))
    }

    // MARK: - Group reads (for T-0 fallback)

    private func groupUD() -> UserDefaults? { UserDefaults(suiteName: AppGroups.main) }

    private func readDouble(_ key: String) -> Double? {
        if let v = groupUD()?.object(forKey: key) as? Double { return v }
        if let v = UserDefaults.standard.object(forKey: key) as? Double { return v }
        return nil
    }

    private func readStringArray(_ key: String) -> [String] {
        if let v = groupUD()?.stringArray(forKey: key) { return v }
        return UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    private func guessScheduledEnds(stackID: String, alarmID: String?) -> Date {
        if let id = alarmID {
            if let eff = readDouble("ak.effTarget.\(id)") { return Date(timeIntervalSince1970: eff) }
            if let exp = readDouble("ak.expected.\(id)")  { return Date(timeIntervalSince1970: exp) }
        }
        if let first = readDouble("ak.firstTarget.\(stackID)") { return Date(timeIntervalSince1970: first) }
        return Date()
    }

    private func guessAlarmID(stackID: String) -> String? {
        let ids = readStringArray("alarmkit.ids.\(stackID)")
        if let first = ids.first { return first }
        let alt = readStringArray("ak.ids.\(stackID)")
        return alt.first
    }

    // MARK: - End all

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

    // MARK: - End one

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

    // MARK: - Ensure (prearm & updates)

    func prearmOrUpdate(stackID: String, content st: AlarmActivityAttributes.ContentState) async {
        guard shouldAttemptRequestsNow() else {
            DiagLog.log("[ACT] prearm.skip (gate) stack=\(stackID)")
            return
        }
        mirrorAKStore(for: stackID, state: st)

        await LAEnsure.ensure(
            stackID: stackID,
            stackName: st.stackName,
            stepTitle: st.stepTitle,
            ends: st.ends,
            allowSnooze: st.allowSnooze,
            alarmID: st.alarmID,
            theme: st.theme,
            firedAt: st.firedAt
        )
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

    // MARK: - Fired (with T-0 creation fallback)

    func markFired(stackID: String, alarmID: String, ends: Date) async {
        await _markFiredCommon(stackID: stackID, alarmID: alarmID, ends: ends)
    }
    func markFired(stackID: String, id: String, ends: Date) async { await _markFiredCommon(stackID: stackID, alarmID: id, ends: ends) }

    func markFired(stackID: String, alarmID: String) async {
        if let act = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) {
            await _markFiredCommon(stackID: stackID, alarmID: alarmID, ends: act.content.state.ends)
        } else {
            let ends = guessScheduledEnds(stackID: stackID, alarmID: alarmID)
            await _markFiredCommon(stackID: stackID, alarmID: alarmID, ends: ends)
        }
    }
    func markFired(stackID: String, id: String) async { await markFired(stackID: stackID, alarmID: id) }

    func markFired(stackID: String) async {
        if let act = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) {
            await _markFiredCommon(stackID: stackID, alarmID: act.content.state.alarmID, ends: act.content.state.ends)
        } else {
            let alarmID = guessAlarmID(stackID: stackID) ?? "la-\(stackID)"
            let ends = guessScheduledEnds(stackID: stackID, alarmID: alarmID)
            await _markFiredCommon(stackID: stackID, alarmID: alarmID, ends: ends)
        }
    }

    private func _markFiredCommon(stackID: String, alarmID: String, ends: Date) async {
        if let act = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == stackID }) {
            var st = act.content.state
            st.firedAt = Date()
            st.ends = ends
            mirrorAKStore(for: stackID, state: st)
            await LAEnsure.ensure(
                stackID: stackID,
                stackName: st.stackName,
                stepTitle: st.stepTitle,
                ends: st.ends,
                allowSnooze: st.allowSnooze,
                alarmID: alarmID,
                theme: st.theme,
                firedAt: st.firedAt
            )
            DiagLog.log("[ACT] markFiredNow (update) stack=\(stackID) step=\(st.stepTitle) firedAt=\(DiagLog.f(st.firedAt ?? Date())) ends=\(DiagLog.f(ends)) id=\(alarmID)")
            LADiag.logAuthAndActive(from: "markFiredNow.update", stackID: stackID, expectingAlarmID: alarmID)
            LADiag.logTimer(whereFrom: "markFiredNow.update", start: st.firedAt, end: st.ends)
            return
        }

        DiagLog.log("[ACT] markFiredNow() no activity → creating at T0")
        await LAEnsure.ensureAtFireTime(
            stackID: stackID,
            stackName: "Alarm",
            stepTitle: "Ringing",
            scheduledEnds: ends,
            alarmID: alarmID,
            theme: ThemeMap.payload(for: "Default")
        )
        LAEnsure.logFinalPresence(present: true, reason: "created")
        LADiag.logAuthAndActive(from: "markFiredNow.created", stackID: stackID, expectingAlarmID: alarmID)
        LADiag.logTimer(whereFrom: "markFiredNow.created", start: Date(), end: ends)
    }

    // MARK: - Legacy “bridge” compatibility (reuse instead of starting new)

    func startBridgeIfNeeded(
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
        mirrorAKStore(for: stackID, state: st)
        await LAEnsure.ensure(
            stackID: stackID,
            stackName: stackName,
            stepTitle: stepTitle,
            ends: ends,
            allowSnooze: allowSnooze,
            alarmID: alarmID,
            theme: theme,
            firedAt: nil
        )
    }
}
