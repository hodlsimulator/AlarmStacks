//
//  LiveActivityManager.swift
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

// MARK: - Key helpers

private func storageKey(forStackID stackID: String) -> String { "alarmkit.ids.\(stackID)" }
private func stackIDKey(for id: UUID) -> String { "ak.stackID.\(id.uuidString)" }
private func offsetFromFirstKey(for id: UUID) -> String { "ak.offsetFromFirst.\(id.uuidString)" }
private func firstTargetKey(forStackID id: String) -> String { "ak.firstTarget.\(id)" }
private func allowSnoozeKey(for id: UUID) -> String { "ak.allowSnooze.\(id.uuidString)" }
private func accentHexKey(for id: UUID) -> String { "ak.accentHex.\(id.uuidString)" }
private func stackNameKey(for id: UUID) -> String { "ak.stackName.\(id.uuidString)" }
private func stepTitleKey(for id: UUID) -> String { "ak.stepTitle.\(id.uuidString)" }
private func expectedKey(for id: UUID) -> String { "ak.expected.\(id.uuidString)" }
private func effTargetKey(for id: UUID) -> String { "ak.effTarget.\(id.uuidString)" }

// MARK: - Unified defaults (read Group first, then standard)

private enum UD {
    static let group = UserDefaults(suiteName: "group.com.hodlsimulator.alarmstacks")

    static func rString(_ key: String) -> String? {
        if let v = group?.string(forKey: key) { return v }
        return UserDefaults.standard.string(forKey: key)
    }
    static func rStringArray(_ key: String) -> [String] {
        if let v = group?.stringArray(forKey: key) { return v }
        return UserDefaults.standard.stringArray(forKey: key) ?? []
    }
    static func rDouble(_ key: String) -> Double {
        if let v = group?.object(forKey: key) as? Double { return v }
        return (UserDefaults.standard.object(forKey: key) as? Double) ?? 0
    }
    static func rBool(_ key: String, default def: Bool = false) -> Bool {
        if let v = group?.object(forKey: key) as? Bool { return v }
        if let v = UserDefaults.standard.object(forKey: key) as? Bool { return v }
        return def
    }
}

// MARK: - Misc

/// Don’t surface the LA if the earliest step is too far away (prevents “in 23h” flash).
private let LA_NEAR_WINDOW: TimeInterval = 2 * 60 * 60 // 2h

/// When leaving the app, allow earlier prewarm so we don’t get blocked later.
/// ⬅️ Bumped to the full near window (2h) so we can start while the app is still foreground.
private let LEAVE_PREWARM_WINDOW: TimeInterval = LA_NEAR_WINDOW

/// Retry cadence + horizon for transient `visibility` / `targetMaximumExceeded`
private let RETRY_TICK: TimeInterval = 5        // try every 5s
private let RETRY_AFTER_TARGET: TimeInterval = 180 // keep trying up to +3m after target

/// Foreground tick cadence to proactively start/update LAs while visible.
private let FOREGROUND_TICK: TimeInterval = 30

/// Bridge fallback: only create/update an LA when we’re very close.
private let BRIDGE_PREARM_LEAD: TimeInterval = 90 // last 90s only

/// Hard minimum lead time (matches the planner) to avoid the OS late-start guardrails.
private let HARD_MIN_LEAD_SECONDS: TimeInterval = 48

/// The stack ID we’ll use for the bridge fallback LA.
private let BRIDGE_STACK_ID = "bridge"

@inline(__always)
private func isAppActive() -> Bool {
    #if canImport(UIKit)
    return UIApplication.shared.applicationState == .active
    #else
    return true
    #endif
}

@inline(__always)
private func isDeviceUnlocked() -> Bool {
    #if canImport(UIKit)
    return UIApplication.shared.isProtectedDataAvailable
    #else
    return true
    #endif
}

/// Central eligibility question for *any* Activity.request
extension LiveActivityManager {
    static func shouldAttemptRequestsNow() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled && isAppActive() && isDeviceUnlocked()
    }
}

/// Try to pull a stackID string out of any object (e.g. your `Stack` model)
private func extractStackIDString(from any: Any) -> String? {
    if let s = any as? String { return s }
    let m = Mirror(reflecting: any)
    for child in m.children {
        guard let label = child.label?.lowercased() else { continue }
        if label == "id" || label == "stackid" || label == "identifier" {
            if let s = child.value as? String { return s }
            if let u = child.value as? UUID { return u.uuidString }
        }
        if label == "uuid" || label == "uuidstring" {
            if let u = child.value as? UUID { return u.uuidString }
            if let s = child.value as? String { return s }
        }
    }
    return nil
}

private func resolveStackIDFromAlarmID(_ alarmID: String) -> String? {
    guard let u = UUID(uuidString: alarmID) else { return nil }
    return UD.rString(stackIDKey(for: u))
}

// MARK: - Manager

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    /// Call this once early (e.g. App init) to register lifecycle observers
    /// and start the foreground cadence immediately when active.
    static func activate() {
        let mgr = LiveActivityManager.shared
        if isAppActive() {
            Task { @MainActor in
                await mgr._onDidBecomeActive()
                await mgr.prearmFromBridgeIfNeeded() // immediate bridge prearm try
            }
        }
    }

    #if canImport(UIKit)
    private var uiObservers: [NSObjectProtocol] = []
    private var fgTimer: Timer?
    #endif

    private init() {
        #if canImport(UIKit)
        uiObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?._onWillResignActive() }
            }
        )
        uiObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?._onWillEnterForeground() }
            }
        )
        uiObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?._onDidBecomeActive() }
            }
        )
        uiObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Device just unlocked → try again immediately.
                Task { @MainActor in await self?._onProtectedDataAvailable() }
            }
        )
        #endif
    }

    deinit {
        #if canImport(UIKit)
        for obs in uiObservers { NotificationCenter.default.removeObserver(obs) }
        fgTimer?.invalidate()
        fgTimer = nil
        #endif
    }

    struct Candidate {
        let id: String
        let date: Date
        let stackName: String
        let stepTitle: String
        let allowSnooze: Bool
        let accentHex: String?
    }

    // MARK: Public API (compat shims)

    static func start(for stack: Any, calendar: Calendar) {
        if let id = extractStackIDString(from: stack) {
            Task { @MainActor in await LiveActivityManager.shared.sync(stackID: id, reason: "start(for:calendar:)") }
        } else {
            MiniDiag.log("[ACT] start WARN could not extract stackID from \(type(of: stack))")
        }
    }

    static func start(stackID: String, calendar: Calendar) {
        Task { @MainActor in await LiveActivityManager.shared.sync(stackID: stackID, reason: "start(stackID:calendar:)") }
    }

    static func start(_ stackID: String) {
        Task { @MainActor in await LiveActivityManager.shared.sync(stackID: stackID, reason: "start(_:)") }
    }

    // MARK: - Visibility/limit retry

    private var retryTasks: [String: Task<Void, Never>] = [:]

    private func cancelRetry(for stackID: String) {
        retryTasks.removeValue(forKey: stackID)?.cancel()
    }

    /// Retry until a little after the target (or until success), with a **fast 5s cadence**.
    private func scheduleRetry(for stackID: String, until deadline: Date) {
        guard retryTasks[stackID] == nil else { return }
        MiniDiag.log("[ACT] retry.schedule stack=\(stackID) until=\(deadline)")
        retryTasks[stackID] = Task { [weak self] in
            while !Task.isCancelled {
                if Date() > deadline { break }
                try? await Task.sleep(nanoseconds: UInt64(RETRY_TICK * 1_000_000_000))
                if Task.isCancelled { break }
                Task { @MainActor in
                    await LiveActivityManager.shared.sync(stackID: stackID, reason: "retry.timer")
                }
            }
            let _: Void = await MainActor.run { [weak self] in
                self?.retryTasks[stackID] = nil
            }
        }
    }

    // MARK: Primary entrypoint

    /// - Parameter nearWindowOverride:
    ///   Use to temporarily tighten/loosen the visibility guard (e.g. when leaving the app).
    func sync(stackID: String,
              reason: String = "sync",
              excludeID: String? = nil,
              nearWindowOverride: TimeInterval? = nil) async {

        // Local kill-switch
        if LAFlags.deviceDisabled {
            MiniDiag.log("[ACT] skip stack=\(stackID) device.disabled")
            return
        }

        // If the user has globally disabled activities, don’t churn.
        let auth = ActivityAuthorizationInfo()
        if !auth.areActivitiesEnabled {
            MiniDiag.log("[ACT] skip stack=\(stackID) auth.disabled")
            return
        }

        let now = Date()
        let existing = Activity<AlarmActivityAttributes>.activities.first { $0.attributes.stackID == stackID }

        guard let chosen = nextCandidate(for: stackID, excludeID: excludeID, now: now) else {
            if let a = existing {
                let st = a.content.state
                await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                MiniDiag.log("[ACT] refresh.end stack=\(stackID) no-future → end")
            }
            cancelRetry(for: stackID)
            return
        }

        // Far-future guard — avoid early “in 23h” flashes.
        let lead = chosen.date.timeIntervalSince(now)
        let window = nearWindowOverride ?? LA_NEAR_WINDOW
        if lead > window {
            if let a = existing {
                // Do NOT end while backgrounded; keep whatever is visible.
                if isAppActive() {
                    let st = a.content.state
                    await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                    MiniDiag.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → end")
                } else {
                    MiniDiag.log("[ACT] refresh.keep stack=\(stackID) far-future lead=\(Int(lead))s (bg) → keep")
                }
            } else {
                MiniDiag.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → no-op")
            }
            cancelRetry(for: stackID)
            return
        }

        // Late-start guard: if we’re inside the OS’s late window and have no activity, don’t thrash.
        if existing == nil, lead < HARD_MIN_LEAD_SECONDS {
            MiniDiag.log("[ACT] start SKIP reason=late-window lead=\(Int(lead))s stack=\(stackID)")
            let stopBy = chosen.date.addingTimeInterval(RETRY_AFTER_TARGET)
            scheduleRetry(for: stackID, until: stopBy)
            return
        }

        var next = AlarmActivityAttributes.ContentState(
            stackName: chosen.stackName,
            stepTitle: chosen.stepTitle,
            ends: chosen.date,
            allowSnooze: chosen.allowSnooze,
            alarmID: chosen.id,
            firedAt: nil
        )

        // Preserve theme if we already have one.
        if let theme = existing?.content.state.theme {
            next.theme = theme
        }

        if let a = existing {
            let st = a.content.state
            if st.stackName == next.stackName &&
               st.stepTitle == next.stepTitle &&
               st.ends == next.ends &&
               st.allowSnooze == next.allowSnooze &&
               st.firedAt == nil &&
               st.alarmID == next.alarmID {
                return
            }
            await a.update(ActivityContent(state: next, staleDate: nil))
            MiniDiag.log("[ACT] refresh.update stack=\(stackID) step=\(next.stepTitle) ends=\(next.ends) id=\(next.alarmID)")
            LADiag.logTimer(whereFrom: "refresh.update", start: nil, end: next.ends)
            LADiag.logAuthAndActive(from: "refresh.update", stackID: stackID, expectingAlarmID: next.alarmID)
            cancelRetry(for: stackID)
            return
        }

        // Proactively keep the cap to avoid “maximum number of activities” on request.
        if Activity<AlarmActivityAttributes>.activities.count > 0 {
            await cleanupOverflow(keeping: nil)
        }

        // If app is not active or device is locked, defer with a fast retry window.
        guard isAppActive(), isDeviceUnlocked() else {
            let stopBy = chosen.date.addingTimeInterval(RETRY_AFTER_TARGET)
            MiniDiag.log("[ACT] start.defer stack=\(stackID) not-eligible(fg=\(isAppActive()) unlock=\(isDeviceUnlocked()))")
            scheduleRetry(for: stackID, until: stopBy)
            return
        }

        do {
            _ = try Activity.request(
                attributes: AlarmActivityAttributes(stackID: stackID),
                content: ActivityContent(state: next, staleDate: nil),
                pushType: nil
            )
            MiniDiag.log("[ACT] start stack=\(stackID) step=\(next.stepTitle) ends=\(next.ends) id=\(next.alarmID)")
            LADiag.logTimer(whereFrom: "start", start: nil, end: next.ends)
            LADiag.logAuthAndActive(from: "start", stackID: stackID, expectingAlarmID: next.alarmID)
            cancelRetry(for: stackID)
        } catch {
            let msg = String(describing: error)
            MiniDiag.log("[ACT] start FAILED stack=\(stackID) error=\(msg)")
            LADiag.logAuthAndActive(from: "start.failed", stackID: stackID, expectingAlarmID: next.alarmID)

            // If OS thinks there are “too many”, end extras so a later request can succeed.
            if msg.localizedCaseInsensitiveContains("maximum number of activities") ||
               msg.localizedCaseInsensitiveContains("targetMaximumExceeded") {
                await cleanupOverflow(keeping: nil)
                let stopBy = chosen.date.addingTimeInterval(RETRY_AFTER_TARGET)
                scheduleRetry(for: stackID, until: stopBy)
                return
            }
            // Visibility: likely background/locked. Keep trying a bit past target with fast cadence.
            if msg.localizedCaseInsensitiveContains("visibility") {
                let stopBy = chosen.date.addingTimeInterval(RETRY_AFTER_TARGET)
                scheduleRetry(for: stackID, until: stopBy)
            }
        }
    }

    /// If OS complains about "maximum number of activities", end extras so a later request can succeed.
    private func cleanupOverflow(keeping keep: String?) async {
        let acts = Activity<AlarmActivityAttributes>.activities
        if acts.count > 0 {
            for a in acts {
                if let keep, a.attributes.stackID == keep { continue }
                let st = a.content.state
                await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                MiniDiag.log("[ACT] cleanup.overflow ended stack=\(a.attributes.stackID) id=\(a.id)")
            }
        }
    }

    // MARK: - “Ringing” mutation

    static func markFiredNow() {
        let acts = Activity<AlarmActivityAttributes>.activities
        guard let a = acts.min(by: {
            abs($0.content.state.ends.timeIntervalSinceNow) <
            abs($1.content.state.ends.timeIntervalSinceNow)
        }) else {
            MiniDiag.log("[ACT] markFiredNow() no active activities; ignoring")
            return
        }
        let st = a.content.state
        Task { @MainActor in
            await LiveActivityManager.shared._markFiredNow(
                stackID: a.attributes.stackID,
                alarmID: st.alarmID,
                firedAt: Date(),
                ends: st.ends,
                stepTitle: nil
            )
        }
    }

    static func markFiredNow(stackID: String, step: String, firedAt: Date, ends: Date, id: String) {
        Task { @MainActor in await LiveActivityManager.shared._markFiredNow(stackID: stackID, alarmID: id, firedAt: firedAt, ends: ends, stepTitle: step) }
    }
    static func markFiredNow(stackID: String, stepTitle: String, firedAt: Date, ends: Date, alarmID: String) {
        Task { @MainActor in await LiveActivityManager.shared._markFiredNow(stackID: stackID, alarmID: alarmID, firedAt: firedAt, ends: ends, stepTitle: stepTitle) }
    }
    static func markFiredNow(stackID: String, alarmID: String, firedAt: Date, ends: Date) {
        Task { @MainActor in await LiveActivityManager.shared._markFiredNow(stackID: stackID, alarmID: alarmID, firedAt: firedAt, ends: ends, stepTitle: nil) }
    }
    static func markFiredNow(stackIDFromAlarm id: String) {
        if let sid = resolveStackIDFromAlarmID(id) {
            Task { @MainActor in await LiveActivityManager.shared._markFiredNow(stackID: sid, alarmID: id, firedAt: Date(), ends: Date(), stepTitle: nil) }
        } else {
            MiniDiag.log("[ACT] markFiredNow WARN no stackID mapping for alarm \(id)")
        }
    }
    static func markFiredNow(stack: Any, id: String) {
        if let sid = extractStackIDString(from: stack) {
            Task { @MainActor in await LiveActivityManager.shared._markFiredNow(stackID: sid, alarmID: id, firedAt: Date(), ends: Date(), stepTitle: nil) }
        } else {
            MiniDiag.log("[ACT] markFiredNow WARN could not extract stackID from \(type(of: stack))")
        }
    }

    private func _markFiredNow(stackID: String, alarmID: String?, firedAt: Date, ends: Date, stepTitle: String?) async {
        var activity = Activity<AlarmActivityAttributes>.activities.first { $0.attributes.stackID == stackID }
        if activity == nil {
            await sync(stackID: stackID, reason: "markFired.ensure")
            activity = Activity<AlarmActivityAttributes>.activities.first { $0.attributes.stackID == stackID }
        }
        guard let a = activity else { return }

        var st = a.content.state
        st.firedAt = firedAt
        st.ends = ends
        if let stepTitle { st.stepTitle = stepTitle }
        if let alarmID { st.alarmID = alarmID }

        await a.update(ActivityContent(state: st, staleDate: nil))
        MiniDiag.log("[ACT] markFiredNow stack=\(stackID) step=\(st.stepTitle) firedAt=\(firedAt) ends=\(ends) id=\(st.alarmID)")
        LADiag.logTimer(whereFrom: "markFiredNow", start: firedAt, end: st.ends)
        LADiag.logAuthAndActive(from: "markFiredNow", stackID: stackID, expectingAlarmID: st.alarmID)
    }

    // MARK: - Candidate selection

    private func nextCandidate(for stackID: String, excludeID: String?, now: Date) -> Candidate? {
        let ids = UD.rStringArray(storageKey(forStackID: stackID))
        guard !ids.isEmpty else { return nil }

        let firstEpoch = UD.rDouble(firstTargetKey(forStackID: stackID))

        var best: Candidate?
        for s in ids {
            if let excludeID, s == excludeID { continue }
            guard let uuid = UUID(uuidString: s) else { continue }

            let stackName = UD.rString(stackNameKey(for: uuid)) ?? "Alarm"
            let stepTitle = UD.rString(stepTitleKey(for: uuid)) ?? "Step"
            let allow     = UD.rBool(allowSnoozeKey(for: uuid), default: false)
            let hx        = UD.rString(accentHexKey(for: uuid))

            let effEpoch  = UD.rDouble(effTargetKey(for: uuid))
            let expEpoch  = UD.rDouble(expectedKey(for: uuid))
            let offAny    = (UD.group?.object(forKey: offsetFromFirstKey(for: uuid))
                             ?? UserDefaults.standard.object(forKey: offsetFromFirstKey(for: uuid))) as? Double

            let date: Date? = {
                if effEpoch > 0 { return Date(timeIntervalSince1970: effEpoch) }
                if expEpoch > 0 { return Date(timeIntervalSince1970: expEpoch) }
                if firstEpoch > 0, let off = offAny { return Date(timeIntervalSince1970: firstEpoch + off) }
                return nil
            }()

            // tolerate slight past skew to keep current one alive
            guard let d = date, d >= now.addingTimeInterval(-2) else { continue }

            if let b = best {
                if d < b.date {
                    best = Candidate(id: uuid.uuidString, date: d, stackName: stackName, stepTitle: stepTitle, allowSnooze: allow, accentHex: hx)
                }
            } else {
                best = Candidate(id: uuid.uuidString, date: d, stackName: stackName, stepTitle: stepTitle, allowSnooze: allow, accentHex: hx)
            }
        }
        return best
    }

    // MARK: - Discover stacks so we can prewarm while foreground

    func allKnownStackIDs() -> [String] {
        var out = Set<String>()
        let keyPrefix = "alarmkit.ids."

        func harvest(_ dict: [String: Any]) {
            for (k, _) in dict where k.hasPrefix(keyPrefix) {
                let sid = String(k.dropFirst(keyPrefix.count))
                out.insert(sid)
            }
        }

        harvest(UserDefaults.standard.dictionaryRepresentation())
        if let grp = UD.group?.dictionaryRepresentation() {
            harvest(grp)
        }
        return Array(out)
    }

    // MARK: - Foreground cadence and app-life handlers

    private func startForegroundTick() {
        #if canImport(UIKit)
        stopForegroundTick()
        fgTimer = Timer.scheduledTimer(withTimeInterval: FOREGROUND_TICK, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ids = self.allKnownStackIDs()
                if ids.isEmpty {
                    // Fallback: when we don't know any stack IDs yet, try the bridge prearm.
                    await self.prearmFromBridgeIfNeeded()
                } else {
                    for sid in ids {
                        await self.sync(stackID: sid, reason: "fg.tick")
                    }
                }
            }
        }
        RunLoop.main.add(fgTimer!, forMode: .common)
        #endif
    }

    private func stopForegroundTick() {
        #if canImport(UIKit)
        fgTimer?.invalidate()
        fgTimer = nil
        #endif
    }

    private func _onWillResignActive() async {
        #if canImport(UIKit)
        stopForegroundTick()
        #endif
        // Prewarm on exit if the next step is within 2h
        let ids = allKnownStackIDs()
        if ids.isEmpty {
            await prearmFromBridgeIfNeeded(now: .now) // try once on exit too
        } else {
            for sid in ids {
                await sync(stackID: sid, reason: "prewarm.willResignActive", nearWindowOverride: LEAVE_PREWARM_WINDOW)
            }
        }
    }

    private func _onWillEnterForeground() async {
        // We’re about to be visible; if a retry was pending, try immediately.
        for sid in Array(retryTasks.keys) {
            await sync(stackID: sid, reason: "retry.willEnterForeground")
        }
        // Also try a bridge prearm in case we didn't have UD keys yet.
        await prearmFromBridgeIfNeeded()
    }

    private func _onDidBecomeActive() async {
        for sid in Array(retryTasks.keys) {
            await sync(stackID: sid, reason: "retry.didBecomeActive")
        }
        #if canImport(UIKit)
        startForegroundTick()
        #endif
        // Immediate bridge prearm attempt on activation.
        await prearmFromBridgeIfNeeded()
    }

    private func _onProtectedDataAvailable() async {
        // Device just unlocked; try again for any pending stack (helps right after unlock).
        for sid in Array(retryTasks.keys) {
            await sync(stackID: sid, reason: "retry.protectedDataAvailable")
        }
        await prearmFromBridgeIfNeeded()
    }

    // MARK: - Bridge fallback prearm (ensures there is *some* LA near fire)

    /// Uses NextAlarmBridge as a safety net to start/update an LA in the last ~90s
    /// even if AlarmKit’s UD keys/stacks aren’t discoverable yet.
    /// IMPORTANT: Only request when foreground + unlocked + enabled to avoid OS guardrails.
    private func prearmFromBridgeIfNeeded(now: Date = .now) async {
        guard LiveActivityManager.shouldAttemptRequestsNow() else {
            MiniDiag.log("[ACT] bridge.defer not-eligible (fg+unlock+enabled=false)")
            return
        }
        if LAFlags.deviceDisabled { return }

        guard let info = NextAlarmBridge.read() else { return }
        let remain = info.fireDate.timeIntervalSince(now)
        guard remain > 0, remain <= BRIDGE_PREARM_LEAD else { return } // only last ~90s

        // Update existing bridge LA or create a new one.
        if let a = Activity<AlarmActivityAttributes>.activities.first(where: { $0.attributes.stackID == BRIDGE_STACK_ID }) {
            var st = a.content.state
            st.stackName   = info.stackName
            st.stepTitle   = info.stepTitle
            st.ends        = info.fireDate
            st.allowSnooze = false
            st.alarmID     = "" // unknown/not needed for display
            await a.update(ActivityContent(state: st, staleDate: nil))
            MiniDiag.log("[ACT] bridge.update step=\(st.stepTitle) ends=\(st.ends)")
            LADiag.logTimer(whereFrom: "bridge.update", start: nil, end: st.ends)
            return
        }

        // Keep under caps before requesting.
        if Activity<AlarmActivityAttributes>.activities.count > 0 {
            await cleanupOverflow(keeping: nil)
        }

        do {
            let st = AlarmActivityAttributes.ContentState(
                stackName: info.stackName,
                stepTitle: info.stepTitle,
                ends: info.fireDate,
                allowSnooze: false,
                alarmID: "",
                firedAt: nil
            )
            _ = try Activity.request(
                attributes: AlarmActivityAttributes(stackID: BRIDGE_STACK_ID),
                content: ActivityContent(state: st, staleDate: nil),
                pushType: nil
            )
            MiniDiag.log("[ACT] bridge.start step=\(st.stepTitle) ends=\(st.ends)")
            LADiag.logTimer(whereFrom: "bridge.start", start: nil, end: st.ends)
        } catch {
            // Do NOT set a long cooldown here — let app-life hooks retry at next eligibility.
            MiniDiag.log("[ACT] bridge.start FAILED error=\(error)")
        }
    }
}
