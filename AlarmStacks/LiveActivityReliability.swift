//
//  LiveActivityReliability.swift
//  AlarmStacks
//
//  Created by . . on 8/18/25.
//

import Foundation
import ActivityKit
import SwiftUI

/// Lightweight helpers that "ensure" a Live Activity exists/updates for a given stack.
/// This file intentionally avoids referencing any nested `ContentState.Theme` type to keep source-compat
/// with different `ContentState` definitions across versions.
enum LAEnsure {

    // MARK: - Discovery helpers

    /// Return the current `Activity` for a given stackID, if any.
    @MainActor
    static func findExisting(stackID: String) -> Activity<AlarmActivityAttributes>? {
        Activity<AlarmActivityAttributes>.activities.first { $0.attributes.stackID == stackID }
    }

    /// Accepts an optional stackID for legacy call sites that may pass `nil` (labeled).
    @MainActor
    static func findExisting(stackID: String?) -> Activity<AlarmActivityAttributes>? {
        guard let stackID else { return nil }
        return findExisting(stackID: stackID)
    }

    /// Convenience overload (some older call sites might pass unlabeled).
    @MainActor
    static func findExisting(_ stackID: String) -> Activity<AlarmActivityAttributes>? {
        findExisting(stackID: stackID)
    }

    /// Unlabeled optional for call sites like `findExisting(nil)`.
    @MainActor
    static func findExisting(_ stackID: String?) -> Activity<AlarmActivityAttributes>? {
        guard let stackID else { return nil }
        return findExisting(stackID: stackID)
    }

    // MARK: - Presence logging helpers

    /// Canonical presence logger with optional fields and an optional reason.
    @MainActor
    static func logFinalPresence(
        from: String,
        stackID: String? = nil,
        expectingAlarmID: String? = nil,
        reason: String? = nil
    ) {
        let acts = Activity<AlarmActivityAttributes>.activities
        let summary = acts.map { a in
            let sid = a.attributes.stackID
            let st  = a.content.state
            return "\(sid){step=\(st.stepTitle), ends=\(st.ends), id=\(st.alarmID), fired=\(st.firedAt?.timeIntervalSince1970 ?? -1)}"
        }.joined(separator: "; ")

        let reasonPart = (reason?.isEmpty == false) ? " reason=\(reason!)" : ""
        MiniDiag.log("[ACT] presence from=\(from) count=\(acts.count) stacks=[\(summary)] expectSID=\(stackID ?? "-") expectAID=\(expectingAlarmID ?? "-")\(reasonPart)")

        LADiag.logAuthAndActive(from: "presence.\(from)", stackID: stackID ?? "", expectingAlarmID: expectingAlarmID ?? "")
    }

    /// Label alias used by some call sites (`whereFrom:` instead of `from:`).
    @MainActor
    static func logFinalPresence(
        whereFrom: String,
        stackID: String,
        expectingAlarmID: String? = nil,
        reason: String? = nil
    ) {
        logFinalPresence(from: whereFrom, stackID: stackID, expectingAlarmID: expectingAlarmID, reason: reason)
    }

    /// Minimal overload (no stack or alarm expected).
    @MainActor
    static func logFinalPresence(_ from: String, reason: String? = nil) {
        logFinalPresence(from: from, stackID: nil, expectingAlarmID: nil, reason: reason)
    }

    /// Legacy variant that passed a boolean indicating current presence/active state,
    /// plus an optional reason. Kept for source compatibility.
    @MainActor
    static func logFinalPresence(
        whereFrom: String,
        isActive: Bool,
        reason: String? = nil
    ) {
        let note = "active=\(isActive)"
        logFinalPresence(from: whereFrom, stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    /// Some older sites incorrectly used the label `stackID:` but supplied a Bool.
    /// Provide a forgiving overload so those calls still compile and log meaningfully.
    @MainActor
    static func logFinalPresence(
        whereFrom: String,
        stackID: Bool,
        reason: String? = nil
    ) {
        let note = "active=\(stackID)"
        logFinalPresence(from: whereFrom, stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    /// Compatibility overload for call sites that use `present:` instead of `isActive:`,
    /// and still include a `whereFrom:` label.
    @MainActor
    static func logFinalPresence(
        whereFrom: String,
        present: Bool,
        reason: String? = nil
    ) {
        let note = "active=\(present)"
        logFinalPresence(from: whereFrom, stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    /// Ultra-compat: some call sites omit `whereFrom:` entirely. Provide no-label variants.
    @MainActor
    static func logFinalPresence(present: Bool, reason: String? = nil) {
        let note = "active=\(present)"
        logFinalPresence(from: "unknown", stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    @MainActor
    static func logFinalPresence(isActive: Bool, reason: String? = nil) {
        let note = "active=\(isActive)"
        logFinalPresence(from: "unknown", stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    // MARK: - Core entrypoint (new API)

    /// New designated entrypoint: pass a fully-formed ContentState.
    @MainActor
    static func ensure(
        stackID: String,
        state: AlarmActivityAttributes.ContentState
    ) async {
        let existing = findExisting(stackID: stackID)

        // Preserve the existing theme if present and not already set on the incoming state.
        var next = state
        if let inherit = existing?.content.state.theme {
            next.theme = inherit
        }

        if let a = existing {
            let st = a.content.state
            // Skip no-op updates.
            if st.stackName == next.stackName &&
               st.stepTitle == next.stepTitle &&
               st.ends == next.ends &&
               st.allowSnooze == next.allowSnooze &&
               st.alarmID == next.alarmID &&
               st.firedAt == next.firedAt {
                return
            }
            await a.update(ActivityContent(state: next, staleDate: nil))
            MiniDiag.log("[ACT] reliability.update stack=\(stackID) step=\(next.stepTitle) ends=\(next.ends) id=\(next.alarmID)")
            LADiag.logTimer(whereFrom: "reliability.update", start: next.firedAt, end: next.ends)
            LADiag.logAuthAndActive(from: "reliability.update", stackID: stackID, expectingAlarmID: next.alarmID)
        } else {
            do {
                _ = try Activity.request(
                    attributes: AlarmActivityAttributes(stackID: stackID),
                    content: ActivityContent(state: next, staleDate: nil),
                    pushType: nil
                )
                MiniDiag.log("[ACT] reliability.start stack=\(stackID) step=\(next.stepTitle) ends=\(next.ends) id=\(next.alarmID)")
                LADiag.logTimer(whereFrom: "reliability.start", start: next.firedAt, end: next.ends)
                LADiag.logAuthAndActive(from: "reliability.start", stackID: stackID, expectingAlarmID: next.alarmID)
            } catch {
                MiniDiag.log("[ACT] reliability.start FAILED stack=\(stackID) error=\(error)")
                LADiag.logAuthAndActive(from: "reliability.start.failed", stackID: stackID, expectingAlarmID: next.alarmID)
            }
        }
    }

    // MARK: - Fire-time helper (new API)

    /// Ensure the LA reflects the fire-time UI. If missing, create one immediately.
    @MainActor
    static func ensureAtFireTime(
        stackID: String,
        stackName: String,
        stepTitle: String,
        ends: Date,
        alarmID: String,
        theme: Any? = nil // kept only for source-compat; ignored
    ) async {
        if let a = findExisting(stackID: stackID) {
            var st = a.content.state
            st.stackName = stackName
            st.stepTitle = stepTitle
            st.ends      = ends
            st.alarmID   = alarmID
            st.firedAt   = Date()
            await a.update(ActivityContent(state: st, staleDate: nil))
            MiniDiag.log("[ACT] ensureAtFireTime.update stack=\(stackID) step=\(st.stepTitle) firedAt=\(String(describing: st.firedAt)) ends=\(st.ends) id=\(st.alarmID)")
            LADiag.logTimer(whereFrom: "ensureAtFireTime.update", start: st.firedAt, end: st.ends)
            LADiag.logAuthAndActive(from: "ensureAtFireTime.update", stackID: stackID, expectingAlarmID: st.alarmID)
        } else {
            let st = AlarmActivityAttributes.ContentState(
                stackName: stackName,
                stepTitle: stepTitle,
                ends: ends,
                allowSnooze: false,
                alarmID: alarmID,
                firedAt: Date()
            )
            do {
                _ = try Activity.request(
                    attributes: AlarmActivityAttributes(stackID: stackID),
                    content: ActivityContent(state: st, staleDate: nil),
                    pushType: nil
                )
                MiniDiag.log("[ACT] ensureAtFireTime.start stack=\(stackID) step=\(st.stepTitle) ends=\(st.ends) id=\(st.alarmID)")
                LADiag.logTimer(whereFrom: "ensureAtFireTime.start", start: st.firedAt, end: st.ends)
                LADiag.logAuthAndActive(from: "ensureAtFireTime.start", stackID: stackID, expectingAlarmID: st.alarmID)
            } catch {
                MiniDiag.log("[ACT] ensureAtFireTime.start FAILED stack=\(stackID) error=\(error)")
                LADiag.logAuthAndActive(from: "ensureAtFireTime.start.failed", stackID: stackID, expectingAlarmID: st.alarmID)
            }
        }
    }

    // MARK: - Source-compat overloads (legacy call sites)

    /// Legacy signature: explicit fields (firedAt BEFORE theme).
    @MainActor
    static func ensure(
        stackID: String,
        stackName: String,
        stepTitle: String,
        ends: Date,
        allowSnooze: Bool,
        alarmID: String,
        firedAt: Date? = nil,
        theme: Any? = nil // kept for source-compat; ignored
    ) async {
        let st = AlarmActivityAttributes.ContentState(
            stackName: stackName,
            stepTitle: stepTitle,
            ends: ends,
            allowSnooze: allowSnooze,
            alarmID: alarmID,
            firedAt: firedAt
        )
        await ensure(stackID: stackID, state: st)
    }

    /// Legacy signature variant: `theme` BEFORE `firedAt`.
    @MainActor
    static func ensure(
        stackID: String,
        stackName: String,
        stepTitle: String,
        ends: Date,
        allowSnooze: Bool,
        alarmID: String,
        theme: Any? = nil,      // kept for source-compat; ignored
        firedAt: Date? = nil
    ) async {
        await ensure(
            stackID: stackID,
            stackName: stackName,
            stepTitle: stepTitle,
            ends: ends,
            allowSnooze: allowSnooze,
            alarmID: alarmID,
            firedAt: firedAt,
            theme: theme
        )
    }

    /// Legacy label alias: `scheduledEnds:` (firedAt BEFORE theme).
    @MainActor
    static func ensure(
        stackID: String,
        stackName: String,
        stepTitle: String,
        scheduledEnds: Date,
        allowSnooze: Bool,
        alarmID: String,
        firedAt: Date? = nil,
        theme: Any? = nil // kept for source-compat; ignored
    ) async {
        await ensure(
            stackID: stackID,
            stackName: stackName,
            stepTitle: stepTitle,
            ends: scheduledEnds,
            allowSnooze: allowSnooze,
            alarmID: alarmID,
            firedAt: firedAt,
            theme: theme
        )
    }

    /// Legacy label alias: `scheduledEnds:` (theme BEFORE firedAt).
    @MainActor
    static func ensure(
        stackID: String,
        stackName: String,
        stepTitle: String,
        scheduledEnds: Date,
        allowSnooze: Bool,
        alarmID: String,
        theme: Any? = nil,      // kept for source-compat; ignored
        firedAt: Date? = nil
    ) async {
        await ensure(
            stackID: stackID,
            stackName: stackName,
            stepTitle: stepTitle,
            ends: scheduledEnds,
            allowSnooze: allowSnooze,
            alarmID: alarmID,
            firedAt: firedAt,
            theme: theme
        )
    }

    /// Legacy helper alias with `scheduledEnds:` so older sites compile.
    @MainActor
    static func ensureAtFireTime(
        stackID: String,
        stackName: String,
        stepTitle: String,
        scheduledEnds: Date,
        alarmID: String,
        theme: Any? = nil // kept for source-compat; ignored
    ) async {
        await ensureAtFireTime(
            stackID: stackID,
            stackName: stackName,
            stepTitle: stepTitle,
            ends: scheduledEnds,
            alarmID: alarmID,
            theme: theme
        )
    }
}
