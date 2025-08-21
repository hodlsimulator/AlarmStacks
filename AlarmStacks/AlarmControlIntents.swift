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

// MARK: - Local mini diagnostics (same sink key as app)

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

// MARK: - Theme helper

private func colorFromHex(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0
    guard Scanner(string: s).scanHexInt64(&v) else { return Color(.sRGB, red: 0.23, green: 0.48, blue: 1.0, opacity: 1) }
    switch s.count {
    case 6:
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8)  & 0xFF) / 255.0
        let b = Double( v        & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    case 8:
        let r = Double((v >> 24) & 0xFF) / 255.0
        let g = Double((v >> 16) & 0xFF) / 255.0
        let b = Double((v >> 8)  & 0xFF) / 255.0
        let a = Double( v        & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    default:
        return Color(.sRGB, red: 0.23, green: 0.48, blue: 1.0, opacity: 1)
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

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        await MainActor.run {
            try? AlarmManager.shared.stop(id: id)
            MiniDiag.log("AK STOP id=\(id.uuidString)")
        }
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

        let ud = UserDefaults.standard

        // Gate by per-step allowSnooze (default FALSE)
        let allow = (ud.object(forKey: allowSnoozeKey(for: baseID)) as? Bool) ?? false
        if allow == false {
            MiniDiag.log("SNOOZE IGNORED (disabled) id=\(baseID.uuidString)")
            return
        }

        // Read metadata from the base
        let minutes   = max(1, ud.integer(forKey: snoozeMinutesKey(for: baseID)))
        let stackName = ud.string(forKey: stackNameKey(for: baseID)) ?? "Alarm"
        let stepTitle = ud.string(forKey: stepTitleKey(for: baseID)) ?? "Snoozed"
        let carriedName = ud.string(forKey: soundKey(for: baseID))
        let hex = ud.string(forKey: accentHexKey(for: baseID)) ?? ud.string(forKey: "themeAccentHex") ?? "#3A7BFF"
        let tint = colorFromHex(hex)

        // Resolve stack mapping
        guard let stackID = ud.string(forKey: stackIDKey(for: baseID)) else {
            MiniDiag.log("[CHAIN] snooze? base=\(baseID.uuidString) (no stackID)")
            return
        }
        let firstEpoch = ud.double(forKey: firstTargetKey(forStackID: stackID))
        guard firstEpoch > 0 else {
            MiniDiag.log("[CHAIN] snooze? stack=\(stackID) (no first target)")
            return
        }
        let firstDate  = Date(timeIntervalSince1970: firstEpoch)
        let baseOffset = (ud.object(forKey: offsetFromFirstKey(for: baseID)) as? Double) ?? 0
        let isFirst    = abs(baseOffset) < 0.5

        // Nominal (calendar) old time for the base = first + offset
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
        if let existing = ud.string(forKey: snoozeMapKey(for: baseID)),
           let existingID = UUID(uuidString: existing) {
            try? AlarmManager.shared.cancel(id: existingID)
            cleanupMetadata(for: existingID)
            ud.removeObject(forKey: snoozeMapKey(for: baseID))
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
        ud.set(newBase.timeIntervalSince1970, forKey: effTargetKey(for: snoozeID))
        ud.set(snoozeID.uuidString, forKey: snoozeMapKey(for: baseID))
        ud.set(minutes,   forKey: snoozeMinutesKey(for: snoozeID))
        ud.set(stackName, forKey: stackNameKey(for: snoozeID))
        ud.set(stepTitle, forKey: stepTitleKey(for: snoozeID))
        if let n = carriedName, !n.isEmpty { ud.set(n, forKey: soundKey(for: snoozeID)) }
        ud.set(hex, forKey: accentHexKey(for: snoozeID))
        ud.set(true, forKey: allowSnoozeKey(for: snoozeID)) // snooze alert always re-snoozable

        // IMPORTANT: give the snooze its correct chain mapping.
        // If base was first -> snooze becomes new base => offset 0.
        // Else: offset(base) += Δ.
        if isFirst {
            ud.set(stackID, forKey: stackIDKey(for: snoozeID))
            ud.set(0.0,     forKey: offsetFromFirstKey(for: snoozeID)) // ✅ FIX
            ud.set("timer", forKey: kindKey(for: snoozeID))
        } else {
            let newOffset = baseOffset + delta
            ud.set(stackID,   forKey: stackIDKey(for: snoozeID))
            ud.set(newOffset, forKey: offsetFromFirstKey(for: snoozeID))
            ud.set("timer",   forKey: kindKey(for: snoozeID))
        }

        MiniDiag.log("AK snooze schedule base=\(baseID.uuidString) id=\(snoozeID.uuidString) secs=\(snoozeSecs) effTarget=\(newBase) Δ=\(String(format: "%.3fs", delta)) baseOffset=\(String(format: "%.1fs", baseOffset)) isFirst=\(isFirst ? "y":"n")")

        // Apply chain shift
        await shiftChainAfterSnooze(stackID: stackID,
                                    baseID: baseID,
                                    snoozeID: snoozeID,
                                    newBase: newBase,
                                    baseIsFirst: isFirst,
                                    delta: delta,
                                    firstDate: firstDate,
                                    baseOffset: baseOffset,
                                    snoozeSecs: snoozeSecs)
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
        let ud = UserDefaults.standard
        var tracked = ud.stringArray(forKey: storageKey(forStackID: stackID)) ?? []

        if tracked.isEmpty {
            MiniDiag.log("[CHAIN] no tracked IDs for stack=\(stackID); abort shift")
            return
        }

        // Replace base id with the new snooze id in the tracked list
        if let idx = tracked.firstIndex(of: baseID.uuidString) {
            tracked[idx] = snoozeID.uuidString
            ud.set(tracked, forKey: storageKey(forStackID: stackID))
        } else {
            tracked.append(snoozeID.uuidString)
            ud.set(tracked, forKey: storageKey(forStackID: stackID))
        }

        // Update anchor
        if baseIsFirst {
            ud.set(newBase.timeIntervalSince1970, forKey: firstTargetKey(forStackID: stackID))
        } else {
            ud.set(baseOffset + delta, forKey: offsetFromFirstKey(for: baseID))
        }

        MiniDiag.log(String(format: "[CHAIN] shift stack=%@ base=%@ → snooze=%@ newBase=%@ Δ=%+.3fs baseOffset=%.1fs isFirst=%@",
                            stackID, baseID.uuidString, snoozeID.uuidString, newBase.description, delta, baseOffset, baseIsFirst ? "y" : "n"))

        // Reschedule impacted steps — DO NOT gate on 'expected/nominal' keys.
        // Offsets + first date are the single source of truth.
        for oldStr in tracked {
            guard let oldID = UUID(uuidString: oldStr) else { continue }
            if oldID == baseID || oldID == snoozeID { continue }

            let kind = ud.string(forKey: kindKey(for: oldID)) ?? "timer"
            if kind == "fixed" {
                MiniDiag.log("[CHAIN] skip fixed id=\(oldID.uuidString)")
                continue
            }

            guard let off = ud.object(forKey: offsetFromFirstKey(for: oldID)) as? Double else {
                MiniDiag.log("[CHAIN] skip id=\(oldID.uuidString) (no offset)")
                continue
            }
            // Middle-step: only move successors
            if baseIsFirst == false && off <= baseOffset { continue }

            // Carry metadata BEFORE cleanup (fallbacks if missing)
            let stackName  = ud.string(forKey: stackNameKey(for: oldID)) ?? "Alarm"
            let stepTitle  = ud.string(forKey: stepTitleKey(for: oldID)) ?? "Step"
            let allow      = (ud.object(forKey: allowSnoozeKey(for: oldID)) as? Bool) ?? false
            let snoozeMins = ud.integer(forKey: snoozeMinutesKey(for: oldID))
            let carried    = ud.string(forKey: soundKey(for: oldID))
            let hx = ud.string(forKey: accentHexKey(for: oldID)) ?? ud.string(forKey: "themeAccentHex") ?? "#3A7BFF"
            let tint = colorFromHex(hx)

            // New nominal & offset
            let newOffset  = baseIsFirst ? off : (off + delta)
            let newNominal = baseIsFirst ? newBase.addingTimeInterval(off)
                                         : firstDate.addingTimeInterval(newOffset)

            // Enforce ≥60 s lead; IMPORTANT: when base was first, guarantee snooze comes first
            let now = Date()
            let raw = max(0, newNominal.timeIntervalSince(now))
            var secs = max(60, Int(ceil(raw)))
            if baseIsFirst, secs <= snoozeSecs { secs = snoozeSecs + 1 } // tie-breaker: snooze must ring first
            let enforcedStr = secs > Int(ceil(raw)) ? "\(secs)s" : "-"

            // Cancel + cleanup old
            try? AlarmManager.shared.cancel(id: oldID)
            cleanupMetadata(for: oldID)

            // Schedule replacement
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

                // Persist new id metadata (store *nominal* for steps)
                ud.set(newNominal.timeIntervalSince1970, forKey: expectedKey(for: newID))
                ud.set(stackName,  forKey: stackNameKey(for: newID))
                ud.set(stepTitle,  forKey: stepTitleKey(for: newID))
                ud.set(allow,      forKey: allowSnoozeKey(for: newID))
                ud.set(snoozeMins, forKey: snoozeMinutesKey(for: newID))
                if let n = carried, !n.isEmpty { ud.set(n, forKey: soundKey(for: newID)) }
                ud.set(hx, forKey: accentHexKey(for: newID))

                // Preserve mapping
                ud.set(stackID,   forKey: stackIDKey(for: newID))
                ud.set(newOffset, forKey: offsetFromFirstKey(for: newID))
                ud.set(kind,      forKey: kindKey(for: newID))

                // Swap id in tracked list
                if let i = tracked.firstIndex(of: oldStr) { tracked[i] = newID.uuidString }
                ud.set(tracked, forKey: storageKey(forStackID: stackID))

                MiniDiag.log("[CHAIN] resched id=\(newID.uuidString) prev=\(oldID.uuidString) newOffset=\(String(format: "%.1fs", newOffset)) newTarget=\(newNominal) enforcedLead=\(enforcedStr) kind=\(kind) allowSnooze=\(allow)")
            } catch {
                MiniDiag.log("[CHAIN] FAILED to reschedule prev=\(oldID.uuidString) error=\(error)")
            }
        }
    }

    // MARK: Cleanup

    @MainActor
    private func cleanupMetadata(for id: UUID) {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: expectedKey(for: id))
        ud.removeObject(forKey: effTargetKey(for: id))
        ud.removeObject(forKey: snoozeMinutesKey(for: id))
        ud.removeObject(forKey: stackNameKey(for: id))
        ud.removeObject(forKey: stepTitleKey(for: id))
        ud.removeObject(forKey: soundKey(for: id))
        ud.removeObject(forKey: accentHexKey(for: id))
        ud.removeObject(forKey: stackIDKey(for: id))
        ud.removeObject(forKey: offsetFromFirstKey(for: id))
        ud.removeObject(forKey: kindKey(for: id))
        ud.removeObject(forKey: allowSnoozeKey(for: id))
    }
}
