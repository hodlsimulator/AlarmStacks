//
//  LiveActivityManager.swift
//  AlarmStacks
//

import Foundation
import ActivityKit
import SwiftUI

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

// MARK: - Diagnostics

@MainActor
private enum MiniDiag {
    private static let key = "diag.log.lines"
    private static let maxLines = 2000

    private static let local: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        return f
    }()

    static func log(_ message: String) {
        let now = Date()
        let up  = ProcessInfo.processInfo.systemUptime
        let stamp = "\(local.string(from: now)) | up:\(String(format: "%.3f", up))s"
        var lines = UserDefaults.standard.stringArray(forKey: key) ?? []
        lines.append("[\(stamp)] \(message)")
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        UserDefaults.standard.set(lines, forKey: key)
    }
}

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
    private init() {}

    struct Candidate {
        let id: String
        let date: Date
        let stackName: String
        let stepTitle: String
        let allowSnooze: Bool
        let accentHex: String?
    }

    // Primary entrypoint
    func sync(stackID: String, reason: String = "sync", excludeID: String? = nil) async {
        let now = Date()
        let existing = Activity<AlarmActivityAttributes>.activities.first { $0.attributes.stackID == stackID }

        guard let chosen = nextCandidate(for: stackID, excludeID: excludeID, now: now) else {
            if let a = existing {
                let st = a.content.state
                await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                MiniDiag.log("[ACT] refresh.end stack=\(stackID) no-future → end")
            }
            return
        }

        // Far-future guard
        let lead = chosen.date.timeIntervalSince(now)
        if lead > LA_NEAR_WINDOW {
            if let a = existing {
                let st = a.content.state
                await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                MiniDiag.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → end")
            } else {
                MiniDiag.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → no-op")
            }
            return
        }

        let next = AlarmActivityAttributes.ContentState(
            stackName: chosen.stackName,
            stepTitle: chosen.stepTitle,
            ends: chosen.date,
            allowSnooze: chosen.allowSnooze,
            alarmID: chosen.id,
            firedAt: nil
        )

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

            // If this update happened while we were background/locked, nudge visibility.
            #if canImport(UIKit)
            LiveActivityVisibilityRetry.nudgeIfBackground(stackID: stackID)
            #endif
        } else {
            do {
                _ = try Activity.request(
                    attributes: AlarmActivityAttributes(stackID: stackID),
                    content: ActivityContent(state: next, staleDate: nil),
                    pushType: nil
                )
                MiniDiag.log("[ACT] start stack=\(stackID) step=\(next.stepTitle) ends=\(next.ends) id=\(next.alarmID)")
            } catch {
                MiniDiag.log("[ACT] start FAILED stack=\(stackID) error=\(error)")
            }
        }
    }

    // MARK: - Back-compat shims (start)

    /// New preferred: just a stackID (reason optional)
    static func start(stackID: String, reason: String = "start") {
        Task { await LiveActivityManager.shared.sync(stackID: stackID, reason: reason) }
    }

    /// Old sites that passed a Calendar (ignored now)
    static func start(stackID: String, calendar: Calendar, reason: String = "start") {
        start(stackID: stackID, reason: reason)
    }

    /// Sites that pass the whole `Stack` under `stackID:` (your old pattern)
    static func start(stackID stack: Any, calendar: Calendar, reason: String = "start") {
        if let id = extractStackIDString(from: stack) {
            start(stackID: id, reason: reason)
        } else {
            MiniDiag.log("[ACT] start WARN could not extract stackID from \(type(of: stack))")
        }
    }

    /// Sites that call `start(stack: ..., calendar: ...)`
    static func start(stack: Any, calendar: Calendar, reason: String = "start") {
        if let id = extractStackIDString(from: stack) {
            start(stackID: id, reason: reason)
        } else {
            MiniDiag.log("[ACT] start WARN could not extract stackID from \(type(of: stack))")
        }
    }

    /// If someone calls `start(_:)` without labels
    static func start(_ stackID: String, calendar: Calendar) {
        start(stackID: stackID)
    }
    static func start(_ stackID: String) {
        start(stackID: stackID)
    }
    
    // Accept the older "for:" label
    static func start(for stack: Any, calendar: Calendar, reason: String = "start") {
        start(stack: stack, calendar: calendar, reason: reason)
    }
    static func start(for stackID: String, calendar: Calendar, reason: String = "start") {
        start(stackID: stackID, calendar: calendar, reason: reason)
    }
    static func start(for stackID: String) {
        start(stackID: stackID)
    }

    // Accept zero-arg markFiredNow() (pick the most relevant active activity)
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
        Task {
            await LiveActivityManager.shared._markFiredNow(
                stackID: a.attributes.stackID,
                alarmID: st.alarmID,
                firedAt: Date(),
                ends: st.ends,
                stepTitle: nil
            )
        }
    }

    // MARK: - “Ringing” mutation

    static func markFiredNow(stackID: String, step: String, firedAt: Date, ends: Date, id: String) {
        Task { await LiveActivityManager.shared._markFiredNow(stackID: stackID, alarmID: id, firedAt: firedAt, ends: ends, stepTitle: step) }
    }
    static func markFiredNow(stackID: String, stepTitle: String, firedAt: Date, ends: Date, alarmID: String) {
        Task { await LiveActivityManager.shared._markFiredNow(stackID: stackID, alarmID: alarmID, firedAt: firedAt, ends: ends, stepTitle: stepTitle) }
    }
    static func markFiredNow(stackID: String, alarmID: String, firedAt: Date, ends: Date) {
        Task { await LiveActivityManager.shared._markFiredNow(stackID: stackID, alarmID: alarmID, firedAt: firedAt, ends: ends, stepTitle: nil) }
    }
    static func markFiredNow(stackID: String, firedAt: Date, ends: Date, id: String? = nil, step: String? = nil) {
        Task { await LiveActivityManager.shared._markFiredNow(stackID: stackID, alarmID: id, firedAt: firedAt, ends: ends, stepTitle: step) }
    }
    static func markFiredNow(stackID: String, id: String) {
        if let stackID = resolveStackIDFromAlarmID(id) {
            Task { await LiveActivityManager.shared._markFiredNow(stackID: stackID, alarmID: id, firedAt: Date(), ends: Date(), stepTitle: nil) }
        } else {
            MiniDiag.log("[ACT] markFiredNow WARN no stackID mapping for alarm \(id)")
        }
    }
    static func markFiredNow(stack: Any, id: String) {
        if let sid = extractStackIDString(from: stack) {
            Task { await LiveActivityManager.shared._markFiredNow(stackID: sid, alarmID: id, firedAt: Date(), ends: Date(), stepTitle: nil) }
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

        // If we just updated while background/locked (e.g., moving to Step 2), nudge visibility.
        #if canImport(UIKit)
        LiveActivityVisibilityRetry.nudgeIfBackground(stackID: stackID)
        #endif
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

            guard let d = date, d >= now.addingTimeInterval(-2) else { continue }

            if let b = best {
                if d < b.date {
                    best = Candidate(id: uuid.uuidString, date: d, stackName: stringOrDefault(stackName, "Alarm"), stepTitle: stringOrDefault(stepTitle, "Step"), allowSnooze: allow, accentHex: hx)
                }
            } else {
                best = Candidate(id: uuid.uuidString, date: d, stackName: stringOrDefault(stackName, "Alarm"), stepTitle: stringOrDefault(stepTitle, "Step"), allowSnooze: allow, accentHex: hx)
            }
        }
        return best
    }

    private func stringOrDefault(_ s: String, _ def: String) -> String {
        s.isEmpty ? def : s
    }
}
