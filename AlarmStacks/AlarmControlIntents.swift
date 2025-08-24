//
//  AlarmControlIntents.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import AppIntents
import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

nonisolated struct IntentsMetadata: AlarmMetadata {}

// MARK: - Keys (must match AlarmKitScheduler scheduling)

private func storageKey(forStackID stackID: String) -> String { "alarmkit.ids.\(stackID)" }
private func stackIDKey(for id: UUID) -> String { "ak.stackID.\(id.uuidString)" }
private func offsetFromFirstKey(for id: UUID) -> String { "ak.offsetFromFirst.\(id.uuidString)" }
private func firstTargetKey(forStackID id: String) -> String { "ak.firstTarget.\(id)" }
private func kindKey(for id: UUID) -> String { "ak.kind.\(id.uuidString)" }
private func allowSnoozeKey(for id: UUID) -> String { "ak.allowSnooze.\(id.uuidString)" }
private func accentHexKey(for id: UUID) -> String { "ak.accentHex.\(id.uuidString)" }
private func soundKey(for id: UUID) -> String { "ak.soundName.\(id.uuidString)" }

// Nominal (calendar) for step alarms; effective (timer) for snooze/test alarms
private func expectedKey(for id: UUID) -> String { "ak.expected.\(id.uuidString)" }
private func effTargetKey(for id: UUID) -> String { "ak.effTarget.\(id.uuidString)" }

// Mapping: base step id -> active snooze id
private func snoozeMapKey(for base: UUID) -> String { "ak.snooze.map.\(base.uuidString)" }

// Simple metadata keys
private func snoozeMinutesKey(for id: UUID) -> String { "ak.snoozeMinutes.\(id.uuidString)" }
private func stackNameKey(for id: UUID) -> String { "ak.stackName.\(id.uuidString)" }
private func stepTitleKey(for id: UUID) -> String { "ak.stepTitle.\(id.uuidString)" }

// MARK: - Local revision bump (App Group)

@MainActor
private func bumpScheduleRevision(_ reason: String) {
    let suite = UserDefaults(suiteName: "group.com.hodlsimulator.alarmstacks") ?? .standard
    let key = "ak.schedule.revision"
    let next = suite.integer(forKey: key) &+ 1
    suite.set(next, forKey: key)
    suite.synchronize()
    WidgetCenter.shared.reloadAllTimelines()
    MiniDiag.log("[REV] bump reason=\(reason) rev=\(next)")
}

// MARK: - Theme helper

private func colorFromHex(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0
    guard Scanner(string: s).scanHexInt64(&v) else {
        return Color(.sRGB, red: 0.23, green: 0.48, blue: 1.0, opacity: 1)
    }
    switch s.count {
    case 6:
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8)  & 0xFF) / 255.0
        let b = Double( v        & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    case 8:
        let r = Double((v >> 24) & 0xFF) / 255.0
        let g = Double((v >> 16) & 0xFF) / 255.0
        let b = Double((v >>  8) & 0xFF) / 255.0
        let a = Double( v        & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    default:
        return Color(.sRGB, red: 0.23, green: 0.48, blue: 1.0, opacity: 1)
    }
}

// MARK: - Unified defaults shim (reads from Group + Standard; writes to both)

private enum UD {
    static let group = UserDefaults(suiteName: "group.com.hodlsimulator.alarmstacks")

    // Reads
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
    static func rInt(_ key: String, default def: Int = 0) -> Int {
        if let v = group?.object(forKey: key) as? Int { return v }
        if let v = UserDefaults.standard.object(forKey: key) as? Int { return v }
        return def
    }
    static func rBool(_ key: String, default def: Bool = false) -> Bool {
        if let v = group?.object(forKey: key) as? Bool { return v }
        if let v = UserDefaults.standard.object(forKey: key) as? Bool { return v }
        return def
    }

    // Writes (mirror to both to avoid domain skew)
    static func set(_ value: Any?, forKey key: String) {
        if let value = value {
            group?.set(value, forKey: key)
            UserDefaults.standard.set(value, forKey: key)
        } else {
            remove(key)
        }
    }
    static func remove(_ key: String) {
        group?.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// Don’t surface LA if the nearest step is too far away (prevents “in 23h” flashes)
private let LA_NEAR_WINDOW: TimeInterval = 2 * 60 * 60 // 2 hours

// MARK: - Minimal LA refresh (local, avoids depending on LiveActivityManager type)

@MainActor
private func refreshActivityFromAppGroup(stackID: String, excludeID: String? = nil) async {
    let ids: [String] = UD.rStringArray(storageKey(forStackID: stackID))
    let now = Date()

    // Find existing activity for this stack (if any).
    let existing = Activity<AlarmActivityAttributes>.activities
        .first(where: { $0.attributes.stackID == stackID })

    guard ids.isEmpty == false else {
        if let a = existing {
            let st = a.content.state
            await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            MiniDiag.log("[ACT] refresh.end stack=\(stackID) no-tracked → end")
        }
        return
    }

    let firstEpoch = UD.rDouble(firstTargetKey(forStackID: stackID))

    struct Candidate {
        var id: String
        var date: Date
        var stackName: String
        var stepTitle: String
        var allowSnooze: Bool
    }

    var best: Candidate?

    for s in ids {
        if let excludeID, s == excludeID { continue }
        guard let uuid = UUID(uuidString: s) else { continue }

        let stackName = UD.rString(stackNameKey(for: uuid)) ?? "Alarm"
        let stepTitle = UD.rString(stepTitleKey(for: uuid)) ?? "Step"
        let allow     = UD.rBool(allowSnoozeKey(for: uuid), default: false)

        let effEpoch = UD.rDouble(effTargetKey(for: uuid))
        let expEpoch = UD.rDouble(expectedKey(for: uuid))
        let offAny   = (UD.group?.object(forKey: offsetFromFirstKey(for: uuid))
                        ?? UserDefaults.standard.object(forKey: offsetFromFirstKey(for: uuid))) as? Double

        let date: Date? = {
            if effEpoch > 0 { return Date(timeIntervalSince1970: effEpoch) }
            if expEpoch > 0 { return Date(timeIntervalSince1970: expEpoch) }
            if firstEpoch > 0, let off = offAny { return Date(timeIntervalSince1970: firstEpoch + off) }
            return nil
        }()

        guard let d = date else { continue }
        if d < now.addingTimeInterval(-2) { continue } // in the past

        if let b = best {
            if d < b.date {
                best = Candidate(id: uuid.uuidString, date: d, stackName: stackName, stepTitle: stepTitle, allowSnooze: allow)
            }
        } else {
            best = Candidate(id: uuid.uuidString, date: d, stackName: stackName, stepTitle: stepTitle, allowSnooze: allow)
        }
    }

    guard let chosen = best else {
        if let a = existing {
            let st = a.content.state
            await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            MiniDiag.log("[ACT] refresh.end stack=\(stackID) no-future → end")
        }
        return
    }

    // Far-future guard: skip showing “tomorrow” until we have a near event.
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

    // Reuse current theme if present, otherwise rely on default in ContentState init.
    let currentTheme = existing?.content.state.theme

    // Always clear firedAt so we never stick in “ringing”.
    var newState = AlarmActivityAttributes.ContentState(
        stackName: chosen.stackName,
        stepTitle: chosen.stepTitle,
        ends: chosen.date,
        allowSnooze: chosen.allowSnooze,
        alarmID: chosen.id,
        firedAt: nil
    )
    if let theme = currentTheme { newState.theme = theme }

    // Unified path: let LAEnsure handle update vs request.
    await LAEnsure.ensure(stackID: stackID, state: newState)
    MiniDiag.log("[ACT] refresh.ensure stack=\(stackID) step=\(newState.stepTitle) ends=\(newState.ends) id=\(newState.alarmID)")
}

// MARK: - Stop

struct StopAlarmIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop Alarm" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID") var alarmID: String

    init() { self.alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }

        // Stop the ringing alarm.
        try? AlarmManager.shared.stop(id: id)
        MiniDiag.log("AK STOP id=\(id.uuidString)")

        // Resolve stackID from App Group, standard, or from the visible LA that shows this alarmID.
        let resolvedStackID: String? = {
            if let s = UD.rString(stackIDKey(for: id)) { return s }
            if let a = Activity<AlarmActivityAttributes>.activities.first(where: { $0.content.state.alarmID == id.uuidString }) {
                return a.attributes.stackID
            }
            if Activity<AlarmActivityAttributes>.activities.count == 1 {
                return Activity<AlarmActivityAttributes>.activities.first?.attributes.stackID
            }
            return nil
        }()

        if let stackID = resolvedStackID {
            MiniDiag.log("[ACT] stop.resolve stack=\(stackID)")
            // Exclude the just-stopped id so we don't pick it again.
            await refreshActivityFromAppGroup(stackID: stackID, excludeID: id.uuidString)
        } else {
            // Fallback: clear ringing flag on any visible activity.
            MiniDiag.log("[ACT] stop.fallback (no stackID) cleared firedAt on visible activities")
            for activity in Activity<AlarmActivityAttributes>.activities {
                var st = activity.content.state
                if st.firedAt != nil {
                    st.firedAt = nil
                    await activity.update(ActivityContent(state: st, staleDate: nil))
                }
            }
        }

        // Nudge widget timelines.
        bumpScheduleRevision("stop")

        return .result()
    }
}

// MARK: - Snooze (self-contained; correct chain shift for first or middle)

// (UNCHANGED BELOW THIS LINE EXCEPT WHERE YOU CALL refreshActivityFromAppGroup(), which already flows through LAEnsure)
