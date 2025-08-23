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

/// Retry/backoff for transient errors like `visibility` or `targetMaximumExceeded`
private let RETRY_INITIAL_DELAY: TimeInterval = 15
private let RETRY_MAX_DELAY: TimeInterval = 90

/// Foreground tick cadence to proactively start/update LAs while we’re visible.
private let FOREGROUND_TICK: TimeInterval = 30

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
                Task { [weak self] in
                    await self?._onWillResignActive()
                }
            }
        )
        uiObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { [weak self] in
                    await self?._onDidBecomeActive()
                }
            }
        )
        #endif
    }

    deinit {
        #if canImport(UIKit)
        for obs in uiObservers { NotificationCenter.default.removeObserver(obs) }
        // Class is @MainActor; deinit runs on the main actor, so invalidate directly.
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

    /// Retry until a little after the target (or until success).
    private func scheduleRetry(for stackID: String, until deadline: Date) {
        guard retryTasks[stackID] == nil else { return }
        MiniDiag.log("[ACT] retry.schedule stack=\(stackID) until=\(deadline)")
        retryTasks[stackID] = Task { [weak self] in
            var delay = RETRY_INITIAL_DELAY
            while !Task.isCancelled {
                if Date() > deadline { break }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { break }
                Task { @MainActor in
                    await LiveActivityManager.shared.sync(stackID: stackID, reason: "retry.timer")
                }
                delay = min(RETRY_MAX_DELAY, delay * 2)
            }
            let _: Void = await MainActor.run { [weak self] in
                self?.retryTasks[stackID] = nil
            }
        }
    }

    // MARK: Primary entrypoint

    func sync(stackID: String, reason: String = "sync", excludeID: String? = nil) async {
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

        // Far-future guard — end or no-op to avoid “in 23h” flashes.
        let lead = chosen.date.timeIntervalSince(now)
        if lead > LA_NEAR_WINDOW {
            if let a = existing {
                let st = a.content.state
                await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                MiniDiag.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → end")
            } else {
                MiniDiag.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → no-op")
            }
            cancelRetry(for: stackID)
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
            cancelRetry(for: stackID)
            return
        }

        do {
            _ = try Activity.request(
                attributes: AlarmActivityAttributes(stackID: stackID),
                content: ActivityContent(state: next, staleDate: nil),
                pushType: nil
            )
            MiniDiag.log("[ACT] start stack=\(stackID) step=\(next.stepTitle) ends=\(next.ends) id=\(next.alarmID)")
            cancelRetry(for: stackID)
        } catch {
            let msg = String(describing: error)
            MiniDiag.log("[ACT] start FAILED stack=\(stackID) error=\(msg)")
            // If OS thinks there are “too many”, end ours so a later request can succeed.
            if msg.localizedCaseInsensitiveContains("maximum number of activities") ||
               msg.localizedCaseInsensitiveContains("targetMaximumExceeded") {
                await cleanupOverflow(keeping: nil)
                let stopBy = chosen.date.addingTimeInterval(90)
                scheduleRetry(for: stackID, until: stopBy)
                return
            }
            // Visibility: we’re likely background/locked. Keep trying a bit past target.
            if msg.localizedCaseInsensitiveContains("visibility") {
                let stopBy = chosen.date.addingTimeInterval(90)
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
    static func markFiredNow(stackID: String, firedAt: Date, ends: Date, id: String? = nil, step: String? = nil) {
        Task { @MainActor in await LiveActivityManager.shared._markFiredNow(stackID: stackID, alarmID: id, firedAt: firedAt, ends: ends, stepTitle: step) }
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
                for sid in ids {
                    await self.sync(stackID: sid, reason: "fg.tick")
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
        let ids = allKnownStackIDs()
        for sid in ids {
            await sync(stackID: sid, reason: "prewarm.willResignActive")
        }
    }

    private func _onDidBecomeActive() async {
        for sid in Array(retryTasks.keys) {
            await sync(stackID: sid, reason: "retry.didBecomeActive")
        }
        #if canImport(UIKit)
        startForegroundTick()
        #endif
    }
}
