//
//  LiveActivityReliability.swift
//  AlarmStacks
//
//  Created by . . on 8/18/25.
//

import Foundation
import ActivityKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Unified helpers that ensure a Live Activity exists/updates for a given stack,
/// including visibility-aware retries and prearm planning (to avoid “must disarm/rearm”).
@MainActor
enum LAEnsure {

    // MARK: - Discovery helpers

    /// Return the current `Activity` for a given stackID, if any.
    static func findExisting(stackID: String) -> Activity<AlarmActivityAttributes>? {
        Activity<AlarmActivityAttributes>.activities.first { $0.attributes.stackID == stackID }
    }

    /// Accepts an optional stackID for legacy call sites that may pass `nil` (labeled).
    static func findExisting(stackID: String?) -> Activity<AlarmActivityAttributes>? {
        guard let stackID else { return nil }
        return findExisting(stackID: stackID)
    }

    /// Convenience overload (some older call sites might pass unlabeled).
    static func findExisting(_ stackID: String) -> Activity<AlarmActivityAttributes>? {
        findExisting(stackID: stackID)
    }

    /// Unlabeled optional for call sites like `findExisting(nil)`.
    static func findExisting(_ stackID: String?) -> Activity<AlarmActivityAttributes>? {
        guard let stackID else { return nil }
        return findExisting(stackID: stackID)
    }

    // MARK: - Presence logging helpers

    /// Canonical presence logger with optional fields and an optional reason.
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
            return "\(sid){step=\(st.stepTitle), ends=\(DiagLog.f(st.ends)), id=\(st.alarmID), fired=\(st.firedAt.map(DiagLog.f) ?? "-")}"
        }.joined(separator: "; ")

        let reasonPart = (reason?.isEmpty == false) ? " reason=\(reason!)" : ""
        DiagLog.log("[ACT] presence from=\(from) count=\(acts.count) stacks=[\(summary)] expectSID=\(stackID ?? "-") expectAID=\(expectingAlarmID ?? "-")\(reasonPart)")

        LADiag.logAuthAndActive(from: "presence.\(from)", stackID: stackID ?? "", expectingAlarmID: expectingAlarmID ?? "")
    }

    static func logFinalPresence(
        whereFrom: String,
        stackID: String,
        expectingAlarmID: String? = nil,
        reason: String? = nil
    ) {
        logFinalPresence(from: whereFrom, stackID: stackID, expectingAlarmID: expectingAlarmID, reason: reason)
    }

    static func logFinalPresence(_ from: String, reason: String? = nil) {
        logFinalPresence(from: from, stackID: nil, expectingAlarmID: nil, reason: reason)
    }

    static func logFinalPresence(
        whereFrom: String,
        isActive: Bool,
        reason: String? = nil
    ) {
        let note = "active=\(isActive)"
        logFinalPresence(from: whereFrom, stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    static func logFinalPresence(
        whereFrom: String,
        stackID: Bool,
        reason: String? = nil
    ) {
        let note = "active=\(stackID)"
        logFinalPresence(from: whereFrom, stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    static func logFinalPresence(
        whereFrom: String,
        present: Bool,
        reason: String? = nil
    ) {
        let note = "active=\(present)"
        logFinalPresence(from: whereFrom, stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    static func logFinalPresence(present: Bool, reason: String? = nil) {
        let note = "active=\(present)"
        logFinalPresence(from: "unknown", stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    static func logFinalPresence(isActive: Bool, reason: String? = nil) {
        let note = "active=\(isActive)"
        logFinalPresence(from: "unknown", stackID: nil, expectingAlarmID: nil, reason: reason.map { "\(note); \($0)" } ?? note)
    }

    // MARK: - Retry policy (visibility / transient failures)

    /// Backoff delays (nanoseconds). Tuned to be patient with OS visibility flips.
    private static let backoff: [UInt64] = [
        1_200_000_000, // 1.2s
        2_400_000_000, // 2.4s
        4_800_000_000  // 4.8s
    ]

    // MARK: - Initial render clamp (fixes "23h to go" flash)

    /// Prefer a near-term end time on the very first render so we don't flash a far-future target.
    private static let initialMinLeadSeconds: TimeInterval = 60      // your 1-minute lead
    private static let initialClampHorizonSeconds: TimeInterval = 120 // only clamp if proposed end is >2m away

    /// If this is the first render (no existing Activity), clamp the proposed `ends` to now+minLead
    /// when the candidate is far in the future. Subsequent updates are left untouched.
    private static func clampedStateForInitialRender(
        stackID: String,
        original: AlarmActivityAttributes.ContentState
    ) -> AlarmActivityAttributes.ContentState {
        var st = original
        let now = Date()
        let remaining = st.ends.timeIntervalSince(now)

        // Only intervene if the scheduler handed us a far-future target.
        if remaining > initialClampHorizonSeconds {
            let near = now.addingTimeInterval(initialMinLeadSeconds)
            if near < st.ends {
                st.ends = near
            }
        }
        return st
    }

    // MARK: - Prearm planner

    /// Schedule “prearm” re-ensures as we approach the fire time.
    /// Strategy: T-120s, T-90s, T-60s, T-48s (only those still in the future).
    private static let prearmOffsets: [TimeInterval] = [120, 90, 60, 48]

    /// Only one pending prearm timer per stackID.
    private static var prearmTimers: [String: Timer] = [:]

    // MARK: - Core entrypoint

    /// Designated entrypoint: pass a fully-formed ContentState (contains theme).
    static func ensure(
        stackID: String,
        state: AlarmActivityAttributes.ContentState
    ) async {
        // If we already have an LA for this stack, update it as-is.
        if let a = findExisting(stackID: stackID) {
            let content = ActivityContent(state: state, staleDate: nil)
            await a.update(content)
            DiagLog.log("[ACT] reliability.update stack=\(stackID) step=\(state.stepTitle) ends=\(DiagLog.f(state.ends)) id=\(state.alarmID)")
            LADiag.logTimer(whereFrom: "reliability.update", start: state.firedAt, end: state.ends)
            LADiag.logAuthAndActive(from: "reliability.update", stackID: stackID, expectingAlarmID: state.alarmID)
            snapshotState(from: "reliability.update", stackID: stackID, expecting: state.alarmID)
            planPrearmTimers(stackID: stackID, state: state)
            return
        }

        // First render path: clamp far-future ends to a near-term (now+minLead) so UI doesn't show "23h".
        let firstRenderState = clampedStateForInitialRender(stackID: stackID, original: state)

        // Otherwise, attempt to request a new LA (respect app visibility/eligibility).
        do {
            if !appEligibleForLiveActivityStart() {
                DiagLog.log("[ACT] reliability.start FAILED stack=\(stackID) error=visibility")
                LADiag.logAuthAndActive(from: "reliability.start.failed", stackID: stackID, expectingAlarmID: firstRenderState.alarmID)
                snapshotState(from: "reliability.start.failed", stackID: stackID, expecting: firstRenderState.alarmID)
                await kickEnsureRetryIfNeeded(stackID: stackID, state: firstRenderState, attempt: 1)
                return
            }

            let attrs   = AlarmActivityAttributes(stackID: stackID)
            let content = ActivityContent(state: firstRenderState, staleDate: nil)
            _ = try Activity<AlarmActivityAttributes>.request(attributes: attrs, content: content, pushType: nil)

            DiagLog.log("[ACT] reliability.start stack=\(stackID) step=\(firstRenderState.stepTitle) ends=\(DiagLog.f(firstRenderState.ends)) id=\(firstRenderState.alarmID)")
            LADiag.logTimer(whereFrom: "reliability.start", start: firstRenderState.firedAt, end: firstRenderState.ends)
            LADiag.logAuthAndActive(from: "reliability.start", stackID: stackID, expectingAlarmID: firstRenderState.alarmID)
            snapshotState(from: "reliability.start", stackID: stackID, expecting: firstRenderState.alarmID)
            planPrearmTimers(stackID: stackID, state: firstRenderState)
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("visibility") || msg.contains("inactive") || msg.contains("protected data") {
                DiagLog.log("[ACT] reliability.start FAILED stack=\(stackID) error=visibility")
            } else {
                DiagLog.log("[ACT] reliability.start FAILED stack=\(stackID) error=\(error)")
            }
            LADiag.logAuthAndActive(from: "reliability.start.failed", stackID: stackID, expectingAlarmID: firstRenderState.alarmID)
            snapshotState(from: "reliability.start.failed", stackID: stackID, expecting: firstRenderState.alarmID)
            await kickEnsureRetryIfNeeded(stackID: stackID, state: firstRenderState, attempt: 1)
        }
    }

    // MARK: - Fire-time helper

    /// Helper used when the alarm has fired (T-0). Creates if missing, otherwise updates and marks `firedAt`.
    static func ensureAtFireTime(
        stackID: String,
        stackName: String,
        stepTitle: String,
        ends: Date,
        alarmID: String,
        theme: ThemePayload
    ) async {
        if let a = findExisting(stackID: stackID) {
            var st = a.content.state
            st.stackName = stackName
            st.stepTitle = stepTitle
            st.ends      = ends
            st.alarmID   = alarmID
            st.firedAt   = Date()
            st.theme     = theme
            await a.update(ActivityContent(state: st, staleDate: nil))
            DiagLog.log("[ACT] ensureAtFireTime.update stack=\(stackID) step=\(st.stepTitle) firedAt=\(DiagLog.f(st.firedAt ?? Date())) ends=\(DiagLog.f(st.ends)) id=\(st.alarmID)")
            LADiag.logTimer(whereFrom: "ensureAtFireTime.update", start: st.firedAt, end: st.ends)
            LADiag.logAuthAndActive(from: "ensureAtFireTime.update", stackID: stackID, expectingAlarmID: st.alarmID)
            snapshotState(from: "ensureAtFireTime.update", stackID: stackID, expecting: st.alarmID)
            return
        }

        let st = AlarmActivityAttributes.ContentState(
            stackName: stackName,
            stepTitle: stepTitle,
            ends: ends,
            allowSnooze: true,
            alarmID: alarmID,
            firedAt: Date(),
            theme: theme
        )
        await ensure(stackID: stackID, state: st)
    }

    // MARK: - Source-compat overloads (legacy call sites)

    /// Legacy signature: explicit fields (firedAt BEFORE theme).
    static func ensure(
        stackID: String,
        stackName: String,
        stepTitle: String,
        ends: Date,
        allowSnooze: Bool,
        alarmID: String,
        firedAt: Date? = nil,
        theme: Any? = nil // tolerated; if ThemePayload present, it will be used
    ) async {
        let resolvedTheme: ThemePayload? = theme as? ThemePayload
        let st = AlarmActivityAttributes.ContentState(
            stackName: stackName,
            stepTitle: stepTitle,
            ends: ends,
            allowSnooze: allowSnooze,
            alarmID: alarmID,
            firedAt: firedAt,
            theme: resolvedTheme ?? ThemeMap.payload(for: "Default")
        )
        await ensure(stackID: stackID, state: st)
    }

    /// Legacy signature variant: `theme` BEFORE `firedAt`.
    static func ensure(
        stackID: String,
        stackName: String,
        stepTitle: String,
        ends: Date,
        allowSnooze: Bool,
        alarmID: String,
        theme: Any? = nil,      // tolerated; if ThemePayload present, it will be used
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

    /// Helper with strongly-typed theme (matches newer call sites).
    static func ensure(
        stackID: String,
        stackName: String,
        stepTitle: String,
        ends: Date,
        allowSnooze: Bool,
        alarmID: String,
        theme: ThemePayload,
        firedAt: Date? = nil
    ) async {
        let st = AlarmActivityAttributes.ContentState(
            stackName: stackName,
            stepTitle: stepTitle,
            ends: ends,
            allowSnooze: allowSnooze,
            alarmID: alarmID,
            firedAt: firedAt,
            theme: theme
        )
        await ensure(stackID: stackID, state: st)
    }

    /// Legacy label alias: `scheduledEnds:` (firedAt BEFORE theme).
    static func ensure(
        stackID: String,
        stackName: String,
        stepTitle: String,
        scheduledEnds: Date,
        allowSnooze: Bool,
        alarmID: String,
        firedAt: Date? = nil,
        theme: Any? = nil // tolerated; if ThemePayload present, it will be used
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
    static func ensure(
        stackID: String,
        stackName: String,
        stepTitle: String,
        scheduledEnds: Date,
        allowSnooze: Bool,
        alarmID: String,
        theme: Any? = nil,      // tolerated; if ThemePayload present, it will be used
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
    static func ensureAtFireTime(
        stackID: String,
        stackName: String,
        stepTitle: String,
        scheduledEnds: Date,
        alarmID: String,
        theme: Any? = nil // tolerated; if ThemePayload present, it will be used
    ) async {
        let resolvedTheme: ThemePayload = (theme as? ThemePayload) ?? ThemeMap.payload(for: "Default")
        await ensureAtFireTime(
            stackID: stackID,
            stackName: stackName,
            stepTitle: stepTitle,
            ends: scheduledEnds,
            alarmID: alarmID,
            theme: resolvedTheme
        )
    }

    // MARK: - Internal: retries & prearm

    private static func planPrearmTimers(stackID: String, state: AlarmActivityAttributes.ContentState) {
        let now = Date()
        let remain = state.ends.timeIntervalSince(now)
        guard remain > 0 else {
            cancelPrearm(for: stackID)
            return
        }

        // Compute attempt delays (seconds from now).
        let delays = prearmOffsets
            .map { remain - $0 }
            .filter { $0 > 0 }
            .sorted()

        // Log the full plan (delays, to match prior diagnostics).
        let ints = delays.map { Int($0.rounded()) }
        DiagLog.log("[LA] prearm plan stack=\(stackID) effTarget=\(DiagLog.f(state.ends)) attempts=\(ints.isEmpty ? "[]" : "[\(ints.map(String.init).joined(separator: ", "))]")s")

        // Schedule only the next attempt; after it fires, we re-plan for the next slot.
        guard let nextDelay = delays.first else {
            cancelPrearm(for: stackID)
            return
        }

        // Replace any existing timer for this stack.
        cancelPrearm(for: stackID)

        // Timer diagnostic parity.
        LADiag.logTimer(whereFrom: "prearm.schedule", start: nil, end: state.ends)

        let timer = Timer.scheduledTimer(withTimeInterval: nextDelay, repeats: false) { _ in
            Task { @MainActor in
                // On fire: try to ensure again (update if exists, start if possible).
                await LAEnsure.ensure(stackID: stackID, state: state)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        prearmTimers[stackID] = timer
    }

    private static func cancelPrearm(for stackID: String) {
        if let t = prearmTimers.removeValue(forKey: stackID) {
            t.invalidate()
        }
    }

    private static func snapshotState(from whereFrom: String, stackID: String, expecting: String?) {
        let auth = ActivityAuthorizationInfo().areActivitiesEnabled
        let acts = Activity<AlarmActivityAttributes>.activities
        let count = acts.count

        let pairs: [String] = acts.map {
            let sid = $0.attributes.stackID
            let id  = $0.content.state.alarmID
            return "\(sid):\(id)"
        }
        let activeStr: String = "{" + pairs.joined(separator: " ") + "}"

        let seen: String = {
            guard let expecting else { return "n" }
            return acts.contains(where: { $0.content.state.alarmID == expecting }) ? "y" : "n"
        }()

        DiagLog.log("[ACT] state from=\(whereFrom) stack=\(stackID) auth.enabled=\(auth ? "y" : "n") active.count=\(count) active\(activeStr) expecting=\(expecting ?? "") seen=\(seen)")
    }

    private static func appEligibleForLiveActivityStart() -> Bool {
        #if canImport(UIKit)
        let state = UIApplication.shared.applicationState
        // Treat .active and .inactive as eligible (locked/transitioning states often appear as .inactive).
        return (state == .active || state == .inactive) && UIApplication.shared.isProtectedDataAvailable
        #else
        return true
        #endif
    }

    private static func kickEnsureRetryIfNeeded(
        stackID: String,
        state: AlarmActivityAttributes.ContentState,
        attempt: Int
    ) async {
        guard attempt <= backoff.count else { return }

        let lead = Int(state.ends.timeIntervalSince(Date()))
        DiagLog.log("[ACT] ensure.retry(\(attempt)) stack=\(stackID) lead=\(lead)s id=\(state.alarmID)")

        // Sleep off-main; resume on main for ActivityKit call.
        let delay = backoff[attempt - 1]
        await withCheckedContinuation { cont in
            Task.detached {
                try? await Task.sleep(nanoseconds: delay)
                await MainActor.run { cont.resume() }
            }
        }

        // If an activity materialised meanwhile, just update it.
        if let existing = findExisting(stackID: stackID) {
            await existing.update(ActivityContent(state: state, staleDate: nil))
            LADiag.logTimer(whereFrom: "ensure.retry.update", start: state.firedAt, end: state.ends)
            LADiag.logAuthAndActive(from: "reliability.update", stackID: stackID, expectingAlarmID: state.alarmID)
            snapshotState(from: "reliability.update", stackID: stackID, expecting: state.alarmID)
            planPrearmTimers(stackID: stackID, state: state)
            return
        }

        // Still first render; apply the same near-term clamp before requesting.
        let firstRenderState = clampedStateForInitialRender(stackID: stackID, original: state)

        // Try requesting again.
        do {
            if !appEligibleForLiveActivityStart() {
                await kickEnsureRetryIfNeeded(stackID: stackID, state: firstRenderState, attempt: attempt + 1)
                return
            }

            let attrs   = AlarmActivityAttributes(stackID: stackID)
            let content = ActivityContent(state: firstRenderState, staleDate: nil)
            _ = try Activity<AlarmActivityAttributes>.request(attributes: attrs, content: content, pushType: nil)

            DiagLog.log("[ACT] reliability.start stack=\(stackID) step=\(firstRenderState.stepTitle) ends=\(DiagLog.f(firstRenderState.ends)) id=\(firstRenderState.alarmID)")
            LADiag.logTimer(whereFrom: "reliability.start", start: firstRenderState.firedAt, end: firstRenderState.ends)
            LADiag.logAuthAndActive(from: "reliability.start", stackID: stackID, expectingAlarmID: firstRenderState.alarmID)
            snapshotState(from: "reliability.start", stackID: stackID, expecting: firstRenderState.alarmID)
            planPrearmTimers(stackID: stackID, state: firstRenderState)
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("visibility") || msg.contains("inactive") || msg.contains("protected data") {
                DiagLog.log("[ACT] reliability.start FAILED stack=\(stackID) error=visibility")
            } else {
                DiagLog.log("[ACT] reliability.start FAILED stack=\(stackID) error=\(error)")
            }
            LADiag.logAuthAndActive(from: "reliability.start.failed", stackID: stackID, expectingAlarmID: firstRenderState.alarmID)
            snapshotState(from: "reliability.start.failed", stackID: stackID, expecting: firstRenderState.alarmID)
            await kickEnsureRetryIfNeeded(stackID: stackID, state: firstRenderState, attempt: attempt + 1)
        }
    }
}
