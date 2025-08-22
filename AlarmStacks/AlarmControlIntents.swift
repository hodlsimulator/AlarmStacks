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

// MARK: - Mini diagnostics (same sink key as app)

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
        let line = "[\(stamp)] \(message)"
        var lines = UserDefaults.standard.stringArray(forKey: key) ?? []
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        UserDefaults.standard.set(lines, forKey: key)
    }
}

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

    // If nothing changed, skip to avoid churn.
    if let a = existing {
        let st = a.content.state
        if st.stackName == newState.stackName &&
            st.stepTitle == newState.stepTitle &&
            st.ends == newState.ends &&
            st.allowSnooze == newState.allowSnooze &&
            st.firedAt == nil &&
            st.alarmID == newState.alarmID {
            return
        }
        await a.update(ActivityContent(state: newState, staleDate: nil))
        MiniDiag.log("[ACT] refresh.update stack=\(stackID) step=\(newState.stepTitle) ends=\(newState.ends) id=\(newState.alarmID)")
    } else {
        do {
            _ = try Activity.request(
                attributes: AlarmActivityAttributes(stackID: stackID),
                content: ActivityContent(state: newState, staleDate: nil),
                pushType: nil
            )
            MiniDiag.log("[ACT] refresh.start stack=\(stackID) step=\(newState.stepTitle) ends=\(newState.ends) id=\(newState.alarmID)")
        } catch {
            MiniDiag.log("[ACT] refresh request failed stack=\(stackID) error=\(error)")
        }
    }
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

struct SnoozeAlarmIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Snooze Alarm" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID") var alarmID: String

    init() { self.alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        guard let baseID = UUID(uuidString: alarmID) else { return .result() }
        await snoozeOnMain(baseID: baseID)
        return .result()
    }

    // MARK: Core snooze + chain shift

    @MainActor
    private func snoozeOnMain(baseID: UUID) async {
        // Silence the current ring immediately.
        try? AlarmManager.shared.stop(id: baseID)

        // Gate by per-step allowSnooze (default FALSE)
        let allow = UD.rBool(allowSnoozeKey(for: baseID), default: false)
        if allow == false {
            MiniDiag.log("SNOOZE IGNORED (disabled) id=\(baseID.uuidString)")
            return
        }

        // Read metadata from the base
        let minutes   = max(1, UD.rInt(snoozeMinutesKey(for: baseID), default: 1))
        let stackName = UD.rString(stackNameKey(for: baseID)) ?? "Alarm"
        let stepTitle = UD.rString(stepTitleKey(for: baseID)) ?? "Snoozed"
        let carriedName = UD.rString(soundKey(for: baseID))
        let hex = UD.rString(accentHexKey(for: baseID)) ?? UserDefaults.standard.string(forKey: "themeAccentHex") ?? "#3A7BFF"
        let tint = colorFromHex(hex)

        // Resolve stack mapping
        guard let stackID = UD.rString(stackIDKey(for: baseID)) else {
            MiniDiag.log("[CHAIN] snooze? base=\(baseID.uuidString) (no stackID)")
            return
        }
        let firstEpoch = UD.rDouble(firstTargetKey(forStackID: stackID))
        guard firstEpoch > 0 else {
            MiniDiag.log("[CHAIN] snooze? stack=\(stackID) (no first target)")
            return
        }
        let firstDate  = Date(timeIntervalSince1970: firstEpoch)
        let baseOffset = ((UD.group?.object(forKey: offsetFromFirstKey(for: baseID))
                           ?? UserDefaults.standard.object(forKey: offsetFromFirstKey(for: baseID))) as? Double) ?? 0
        let isFirst    = abs(baseOffset) < 0.5

        // Nominal old time for the base = first + offset
        let oldNominal = firstDate.addingTimeInterval(baseOffset)

        // New snooze effective time; always ≥ 60 s lead
        let snoozeSecs = max(60, minutes * 60)
        let newBase    = Date().addingTimeInterval(TimeInterval(snoozeSecs))
        let delta      = newBase.timeIntervalSince(oldNominal)

        // Build alert (snooze ALWAYS allowed)
        let stopBtn   = AlarmButton(text: LocalizedStringResource("Stop"),   textColor: .white, systemImageName: "stop.fill")
        let snoozeBtn = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource("\(stackName) — \(stepTitle)"),
            stopButton: stopBtn,
            secondaryButton: snoozeBtn,
            secondaryButtonBehavior: .countdown
        )
        let attrs = AlarmAttributes<IntentsMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: tint)

        // Cancel any existing mapped snooze for this base
        if let existing = UD.rString(snoozeMapKey(for: baseID)),
           let existingID = UUID(uuidString: existing) {
            try? AlarmManager.shared.cancel(id: existingID)
            cleanupMetadata(for: existingID)
            UD.remove(snoozeMapKey(for: baseID))
        }

        // Schedule the snooze timer
        let snoozeID = UUID()
        do {
            let cfg: AlarmManager.AlarmConfiguration<IntentsMetadata> = .timer(
                duration: TimeInterval(snoozeSecs),
                attributes: attrs,
                stopIntent: StopAlarmIntent(alarmID: snoozeID.uuidString),
                secondaryIntent: SnoozeAlarmIntent(alarmID: snoozeID.uuidString),
                sound: .default
            )
            _ = try await AlarmManager.shared.schedule(id: snoozeID, configuration: cfg)
        } catch {
            MiniDiag.log("AK snooze schedule FAILED base=\(baseID.uuidString) error=\(error)")
            return
        }

        // Persist snooze metadata (effective target only)
        UD.set(newBase.timeIntervalSince1970, forKey: effTargetKey(for: snoozeID))
        UD.set(snoozeID.uuidString,          forKey: snoozeMapKey(for: baseID))
        UD.set(minutes,                      forKey: snoozeMinutesKey(for: snoozeID))
        UD.set(stackName,                    forKey: stackNameKey(for: snoozeID))
        UD.set(stepTitle,                    forKey: stepTitleKey(for: snoozeID))
        if let n = carriedName, !n.isEmpty { UD.set(n, forKey: soundKey(for: snoozeID)) }
        UD.set(hex,                          forKey: accentHexKey(for: snoozeID))
        UD.set(true,                         forKey: allowSnoozeKey(for: snoozeID)) // snooze alert always re-snoozable

        // Snooze mapping for offsets
        if isFirst {
            UD.set(stackID, forKey: stackIDKey(for: snoozeID))
            UD.set(0.0,     forKey: offsetFromFirstKey(for: snoozeID)) // becomes the new base
            UD.set("timer", forKey: kindKey(for: snoozeID))
        } else {
            let newOffset = baseOffset + delta
            UD.set(stackID,   forKey: stackIDKey(for: snoozeID))
            UD.set(newOffset, forKey: offsetFromFirstKey(for: snoozeID))
            UD.set("timer",   forKey: kindKey(for: snoozeID))
        }

        MiniDiag.log("AK snooze schedule base=\(baseID.uuidString) id=\(snoozeID.uuidString) secs=\(snoozeSecs) effTarget=\(newBase) Δ=\(String(format: "%.3fs", delta)) baseOffset=\(String(format: "%.1fs", baseOffset)) isFirst=\(isFirst ? "y":"n")")

        // Replace base in tracked list with snooze id, adjust successors
        await shiftChainAfterSnooze(stackID: stackID,
                                    baseID: baseID,
                                    snoozeID: snoozeID,
                                    newBase: newBase,
                                    baseIsFirst: isFirst,
                                    delta: delta,
                                    firstDate: firstDate,
                                    baseOffset: baseOffset,
                                    snoozeSecs: snoozeSecs)

        // Refresh LA to the earliest pending (usually the snooze we just created).
        await refreshActivityFromAppGroup(stackID: stackID)

        // Bump widget revision once per snooze op
        bumpScheduleRevision("snoozeIntent")
    }

    // MARK: Chain shift (first or middle)

    @MainActor
    private func shiftChainAfterSnooze(
        stackID: String,
        baseID: UUID,
        snoozeID: UUID,
        newBase: Date,
        baseIsFirst: Bool,
        delta: TimeInterval,
        firstDate: Date,
        baseOffset: TimeInterval,
        snoozeSecs: Int
    ) async {
        var tracked = UD.rStringArray(storageKey(forStackID: stackID))

        if tracked.isEmpty {
            MiniDiag.log("[CHAIN] no tracked IDs for stack=\(stackID); abort shift")
            return
        }

        // Replace base id with the new snooze id in the tracked list
        if let idx = tracked.firstIndex(of: baseID.uuidString) {
            tracked[idx] = snoozeID.uuidString
            UD.set(tracked, forKey: storageKey(forStackID: stackID))
        } else {
            tracked.append(snoozeID.uuidString)
            UD.set(tracked, forKey: storageKey(forStackID: stackID))
        }

        // Update anchor
        if baseIsFirst {
            UD.set(newBase.timeIntervalSince1970, forKey: firstTargetKey(forStackID: stackID))
        } else {
            UD.set(baseOffset + delta, forKey: offsetFromFirstKey(for: baseID))
        }

        MiniDiag.log(String(format: "[CHAIN] shift stack=%@ base=%@ → snooze=%@ newBase=%@ Δ=%+.3fs baseOffset=%.1fs isFirst=%@",
                            stackID, baseID.uuidString, snoozeID.uuidString, newBase.description, delta, baseOffset, baseIsFirst ? "y" : "n"))

        // Reschedule impacted steps
        for oldStr in tracked {
            guard let oldID = UUID(uuidString: oldStr) else { continue }
            if oldID == baseID || oldID == snoozeID { continue }

            let kind = UD.rString(kindKey(for: oldID)) ?? "timer"
            if kind == "fixed" {
                MiniDiag.log("[CHAIN] skip fixed id=\(oldID.uuidString)")
                continue
            }

            guard let off = (UD.group?.object(forKey: offsetFromFirstKey(for: oldID))
                             ?? UserDefaults.standard.object(forKey: offsetFromFirstKey(for: oldID))) as? Double else {
                MiniDiag.log("[CHAIN] skip id=\(oldID.uuidString) (no offset)")
                continue
            }
            if baseIsFirst == false && off <= baseOffset { continue }

            // Carry metadata BEFORE cleanup (fallbacks if missing)
            let stackName  = UD.rString(stackNameKey(for: oldID)) ?? "Alarm"
            let stepTitle  = UD.rString(stepTitleKey(for: oldID)) ?? "Step"
            let allow      = UD.rBool(allowSnoozeKey(for: oldID), default: false)
            let snoozeMins = UD.rInt(snoozeMinutesKey(for: oldID), default: 1)
            let carried    = UD.rString(soundKey(for: oldID))
            let hx = UD.rString(accentHexKey(for: oldID)) ?? UserDefaults.standard.string(forKey: "themeAccentHex") ?? "#3A7BFF"

            // New nominal & offset
            let newOffset  = baseIsFirst ? off : (off + delta)
            let newNominal = baseIsFirst ? newBase.addingTimeInterval(off)
                                         : firstDate.addingTimeInterval(newOffset)

            // Enforce ≥60 s lead; guarantee snooze is earliest if baseIsFirst
            let now = Date()
            let raw = max(0, newNominal.timeIntervalSince(now))
            var secs = max(60, Int(ceil(raw)))
            if baseIsFirst, secs <= snoozeSecs { secs = snoozeSecs + 1 }
            let enforcedStr = secs > Int(ceil(raw)) ? "\(secs)s" : "-"

            // Cancel previous + cleanup
            try? AlarmManager.shared.cancel(id: oldID)
            cleanupMetadata(for: oldID)

            // Replacement schedule
            let newID = UUID()
            let stopBtn   = AlarmButton(text: LocalizedStringResource("Stop"),   textColor: .white, systemImageName: "stop.fill")
            let alert: AlarmPresentation.Alert = {
                if allow {
                    let snoozeBtn = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
                    return AlarmPresentation.Alert(
                        title: LocalizedStringResource("\(stackName) — \(stepTitle)"),
                        stopButton: stopBtn,
                        secondaryButton: snoozeBtn,
                        secondaryButtonBehavior: .countdown
                    )
                } else {
                    return AlarmPresentation.Alert(
                        title: LocalizedStringResource("\(stackName) — \(stepTitle)"),
                        stopButton: stopBtn,
                        secondaryButton: nil,
                        secondaryButtonBehavior: nil
                    )
                }
            }()
            let tint = colorFromHex(hx)
            let attrs = AlarmAttributes<IntentsMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: tint)
            let stopI   = StopAlarmIntent(alarmID: newID.uuidString)
            let snoozeI = allow ? SnoozeAlarmIntent(alarmID: newID.uuidString) : nil

            do {
                let cfg: AlarmManager.AlarmConfiguration<IntentsMetadata> = .timer(
                    duration: TimeInterval(secs),
                    attributes: attrs,
                    stopIntent: stopI,
                    secondaryIntent: snoozeI,
                    sound: .default
                )
                _ = try await AlarmManager.shared.schedule(id: newID, configuration: cfg)

                // Persist new id metadata
                UD.set(newNominal.timeIntervalSince1970, forKey: expectedKey(for: newID))
                UD.set(stackName,  forKey: stackNameKey(for: newID))
                UD.set(stepTitle,  forKey: stepTitleKey(for: newID))
                UD.set(allow,      forKey: allowSnoozeKey(for: newID))
                UD.set(snoozeMins, forKey: snoozeMinutesKey(for: newID))
                if let n = carried, !n.isEmpty { UD.set(n, forKey: soundKey(for: newID)) }
                UD.set(hx, forKey: accentHexKey(for: newID))

                // Preserve mapping
                UD.set(stackID,   forKey: stackIDKey(for: newID))
                UD.set(newOffset, forKey: offsetFromFirstKey(for: newID))
                UD.set(kind,      forKey: kindKey(for: newID))

                // Swap id in tracked list
                if let i = tracked.firstIndex(of: oldStr) { tracked[i] = newID.uuidString }
                UD.set(tracked, forKey: storageKey(forStackID: stackID))

                MiniDiag.log("[CHAIN] resched id=\(newID.uuidString) prev=\(oldID.uuidString) newOffset=\(String(format: "%.1fs", newOffset)) newTarget=\(newNominal) enforcedLead=\(enforcedStr) kind=\(kind) allowSnooze=\(allow)")
            } catch {
                MiniDiag.log("[CHAIN] FAILED to reschedule prev=\(oldID.uuidString) error=\(error)")
            }
        }
    }

    // MARK: Cleanup

    @MainActor
    private func cleanupMetadata(for id: UUID) {
        UD.remove(expectedKey(for: id))
        UD.remove(effTargetKey(for: id))
        UD.remove(snoozeMinutesKey(for: id))
        UD.remove(stackNameKey(for: id))
        UD.remove(stepTitleKey(for: id))
        UD.remove(soundKey(for: id))
        UD.remove(accentHexKey(for: id))
        UD.remove(stackIDKey(for: id))
        UD.remove(offsetFromFirstKey(for: id))
        UD.remove(kindKey(for: id))
        UD.remove(allowSnoozeKey(for: id))
    }
}
