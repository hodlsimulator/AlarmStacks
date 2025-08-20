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

// MARK: - Keys (must match AlarmKitScheduler)

private func storageKey(forStackID stackID: String) -> String { "alarmkit.ids.\(stackID)" }
private func stackIDKey(for id: UUID) -> String { "ak.stackID.\(id.uuidString)" }
private func offsetFromFirstKey(for id: UUID) -> String { "ak.offsetFromFirst.\(id.uuidString)" }
private func firstTargetKey(forStackID id: String) -> String { "ak.firstTarget.\(id)" }
private func kindKey(for id: UUID) -> String { "ak.kind.\(id.uuidString)" }
private func allowSnoozeKey(for id: UUID) -> String { "ak.allowSnooze.\(id.uuidString)" }
private func accentHexKey(for id: UUID) -> String { "ak.accentHex.\(id.uuidString)" }
private func soundKey(for id: UUID) -> String { "ak.soundName.\(id.uuidString)" }
private func expectedKey(for id: UUID) -> String { "ak.expected.\(id.uuidString)" }
private func snoozeMapKey(for base: UUID) -> String { "ak.snooze.map.\(base.uuidString)" }

// MARK: - Mini diagnostics (write into same log store)

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

// MARK: - Snooze tap (compatible with AKDiag)

@MainActor
private enum SnoozeTapStore {
    private static func key(_ base: UUID) -> String { "ak.snooze.tap.\(base.uuidString)" }
    private struct Tap: Codable { let wall: Date; let up: TimeInterval }

    static func rememberTap(for base: UUID,
                            wall: Date = Date(),
                            up: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let data = try? JSONEncoder().encode(Tap(wall: wall, up: up)) {
            UserDefaults.standard.set(data, forKey: key(base))
        }
        MiniDiag.log("AK SNOOZE TAPPED base=\(base.uuidString)")
    }
}

// MARK: - Theme helpers (avoid app dependencies)

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

@MainActor
private func resolvedAccent(for baseID: UUID) -> (color: Color, hex: String) {
    if let hx = UserDefaults.standard.string(forKey: accentHexKey(for: baseID)), !hx.isEmpty {
        return (colorFromHex(hx), hx)
    }
    if let hx = UserDefaults.standard.string(forKey: "themeAccentHex"), !hx.isEmpty {
        return (colorFromHex(hx), hx)
    }
    let hx = "#3A7BFF"
    return (colorFromHex(hx), hx)
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

// MARK: - Snooze (self-contained; honours per-step allowSnooze)

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

    // MARK: Core snooze + general chain shift (first or middle)

    @MainActor
    private func snoozeOnMain(baseID: UUID) async {
        // Always silence the current alert immediately.
        try? AlarmManager.shared.stop(id: baseID)

        let ud = UserDefaults.standard
        // Honour per-step allowSnooze; default to FALSE if missing.
        let allow = (ud.object(forKey: allowSnoozeKey(for: baseID)) as? Bool) ?? false
        if allow == false {
            MiniDiag.log("SNOOZE IGNORED (disabled) id=\(baseID.uuidString)")
            return
        }

        SnoozeTapStore.rememberTap(for: baseID)

        let minutes   = max(1, ud.integer(forKey: "ak.snoozeMinutes.\(baseID.uuidString)"))
        let stackName = ud.string(forKey: "ak.stackName.\(baseID.uuidString)") ?? "Alarm"
        let stepTitle = ud.string(forKey: "ak.stepTitle.\(baseID.uuidString)") ?? "Snoozed"

        let (accent, accentHex) = resolvedAccent(for: baseID)
        let carriedName = ud.string(forKey: soundKey(for: baseID))

        // Snooze ring itself always allows snoozing again.
        let setSecs = max(60, minutes * 60)
        let id = UUID()
        let now = Date()
        let newBase = now.addingTimeInterval(TimeInterval(setSecs))

        let stopBtn   = AlarmButton(text: LocalizedStringResource("Stop"),   textColor: .white, systemImageName: "stop.fill")
        let snoozeBtn = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource("\(stackName) — \(stepTitle)"),
            stopButton: stopBtn,
            secondaryButton: snoozeBtn,
            secondaryButtonBehavior: .countdown
        )
        let attrs = AlarmAttributes<IntentsMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: accent)
        let stopI   = StopAlarmIntent(alarmID: id.uuidString)
        let snoozeI = SnoozeAlarmIntent(alarmID: id.uuidString)

        do {
            let cfg: AlarmManager.AlarmConfiguration<IntentsMetadata> = .timer(
                duration: TimeInterval(setSecs),
                attributes: attrs,
                stopIntent: stopI,
                secondaryIntent: snoozeI,
                sound: .default
            )
            _ = try await AlarmManager.shared.schedule(id: id, configuration: cfg)

            // Persist the new snooze alarm
            ud.set(newBase.timeIntervalSince1970, forKey: expectedKey(for: id))
            ud.set(id.uuidString, forKey: snoozeMapKey(for: baseID))
            ud.set(minutes, forKey: "ak.snoozeMinutes.\(id.uuidString)")
            ud.set(stackName, forKey: "ak.stackName.\(id.uuidString)")
            ud.set(stepTitle, forKey: "ak.stepTitle.\(id.uuidString)")
            if let n = carriedName, !n.isEmpty { ud.set(n, forKey: soundKey(for: id)) }
            ud.set(accentHex, forKey: accentHexKey(for: id))

            // Attach mapping so future snoozes on this new id work.
            if let stackID = ud.string(forKey: stackIDKey(for: baseID)) {
                let firstEpoch = ud.double(forKey: firstTargetKey(forStackID: stackID))
                let firstDate  = firstEpoch > 0 ? Date(timeIntervalSince1970: firstEpoch) : nil
                let baseOffset = (ud.object(forKey: offsetFromFirstKey(for: baseID)) as? Double) ?? 0
                let oldNominal = (ud.double(forKey: expectedKey(for: baseID)) > 0)
                    ? Date(timeIntervalSince1970: ud.double(forKey: expectedKey(for: baseID)))
                    : firstDate?.addingTimeInterval(baseOffset)
                if firstDate != nil, let oldNom = oldNominal {
                    let delta = newBase.timeIntervalSince(oldNom)
                    let newOffset = baseOffset + delta
                    ud.set(stackID,   forKey: stackIDKey(for: id))
                    ud.set(newOffset, forKey: offsetFromFirstKey(for: id))
                    ud.set("timer",   forKey: kindKey(for: id))
                    ud.set(true,      forKey: allowSnoozeKey(for: id))
                }
            }

            MiniDiag.log("AK snooze schedule base=\(baseID.uuidString) id=\(id.uuidString) set=\(setSecs)s effTarget=\(newBase)")

            // Generalised chain shift: push subsequent steps by delta.
            await shiftChainAfterSnooze(baseID: baseID, newBase: newBase)
        } catch {
            MiniDiag.log("AK snooze schedule FAILED base=\(baseID.uuidString) error=\(error)")
        }
    }

    // MARK: Chain shift logic (first or middle step snooze)

    @MainActor
    private func shiftChainAfterSnooze(baseID: UUID, newBase: Date) async {
        let ud = UserDefaults.standard
        guard let stackID = ud.string(forKey: stackIDKey(for: baseID)) else {
            MiniDiag.log("[CHAIN] shift? base=\(baseID.uuidString) (no stackID found)")
            return
        }

        let firstEpoch = ud.double(forKey: firstTargetKey(forStackID: stackID))
        guard firstEpoch > 0 else {
            MiniDiag.log("[CHAIN] shift? stack=\(stackID) (no first target recorded)")
            return
        }
        let firstDate = Date(timeIntervalSince1970: firstEpoch)

        let baseOffset = (ud.object(forKey: offsetFromFirstKey(for: baseID)) as? Double) ?? 0
        let isFirst = abs(baseOffset) < 0.5

        let baseNominalTS = ud.double(forKey: expectedKey(for: baseID))
        let oldNominal = baseNominalTS > 0 ? Date(timeIntervalSince1970: baseNominalTS)
                                           : firstDate.addingTimeInterval(baseOffset)

        let delta = newBase.timeIntervalSince(oldNominal)

        MiniDiag.log(String(format: "[CHAIN] shift stack=%@ base=%@ newBase=%@ Δ=%+.3fs baseOffset=%.1fs isFirst=%@",
                            stackID, baseID.uuidString, newBase.description, delta, baseOffset, isFirst ? "y" : "n"))

        var ids = ud.stringArray(forKey: storageKey(forStackID: stackID)) ?? []
        if ids.isEmpty {
            MiniDiag.log("[CHAIN] no tracked IDs for stack=\(stackID); abort shift")
            return
        }

        if isFirst {
            ud.set(newBase.timeIntervalSince1970, forKey: firstTargetKey(forStackID: stackID))
        } else {
            ud.set(baseOffset + delta, forKey: offsetFromFirstKey(for: baseID))
        }

        for oldStr in ids {
            guard let oldID = UUID(uuidString: oldStr), oldID != baseID else { continue }
            let kind = ud.string(forKey: kindKey(for: oldID)) ?? "timer"
            if kind == "fixed" { MiniDiag.log("[CHAIN] skip fixed id=\(oldID.uuidString)"); continue }
            guard let off = ud.object(forKey: offsetFromFirstKey(for: oldID)) as? Double else {
                MiniDiag.log("[CHAIN] skip id=\(oldID.uuidString) (no offset)"); continue
            }
            if !isFirst && off <= baseOffset { continue }

            let expectedTS = ud.double(forKey: expectedKey(for: oldID))
            if expectedTS <= 0 { MiniDiag.log("[CHAIN] skip id=\(oldID.uuidString) (no expected; fired)"); continue }

            let allowSnooze = (ud.object(forKey: allowSnoozeKey(for: oldID)) as? Bool) ?? false
            let stackName = ud.string(forKey: "ak.stackName.\(oldID.uuidString)") ?? "Alarm"
            let stepTitle = ud.string(forKey: "ak.stepTitle.\(oldID.uuidString)") ?? "Step"
            let snoozeMins = ud.integer(forKey: "ak.snoozeMinutes.\(oldID.uuidString)")
            let carriedName = ud.string(forKey: soundKey(for: oldID))
            let hex = ud.string(forKey: accentHexKey(for: oldID)) ?? UserDefaults.standard.string(forKey: "themeAccentHex") ?? "#3A7BFF"
            let tint = colorFromHex(hex)

            // New nominal + offset
            let newOffset  = isFirst ? off : (off + delta)
            let newNominal = isFirst ? newBase.addingTimeInterval(off)
                                     : firstDate.addingTimeInterval(newOffset)

            // Enforce ≥60s lead
            let now = Date()
            let raw = max(0, newNominal.timeIntervalSince(now))
            let secs = max(60, Int(ceil(raw)))
            _ = now.addingTimeInterval(TimeInterval(secs)) // silence unused var

            let enforcedStr = secs > Int(ceil(raw)) ? "\(secs)s" : "-"

            try? AlarmManager.shared.cancel(id: oldID)
            cleanupExpectationAndMetadata(for: oldID)

            let newID = UUID()
            let stopBtn   = AlarmButton(text: LocalizedStringResource("Stop"),   textColor: .white, systemImageName: "stop.fill")
            let alert: AlarmPresentation.Alert = {
                if allowSnooze {
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
            let snoozeI = allowSnooze ? SnoozeAlarmIntent(alarmID: newID.uuidString) : nil

            do {
                let cfg: AlarmManager.AlarmConfiguration<IntentsMetadata> = .timer(
                    duration: TimeInterval(secs),
                    attributes: attrs,
                    stopIntent: stopI,
                    secondaryIntent: snoozeI,
                    sound: .default
                )
                _ = try await AlarmManager.shared.schedule(id: newID, configuration: cfg)

                ud.set(newNominal.timeIntervalSince1970, forKey: expectedKey(for: newID))
                ud.set(stackName,  forKey: "ak.stackName.\(newID.uuidString)")
                ud.set(stepTitle,  forKey: "ak.stepTitle.\(newID.uuidString)")
                ud.set(allowSnooze, forKey: allowSnoozeKey(for: newID))
                ud.set(snoozeMins, forKey: "ak.snoozeMinutes.\(newID.uuidString)")
                if let n = carriedName, !n.isEmpty { ud.set(n, forKey: soundKey(for: newID)) }
                ud.set(hex, forKey: accentHexKey(for: newID))

                ud.set(stackID,   forKey: stackIDKey(for: newID))
                ud.set(newOffset, forKey: offsetFromFirstKey(for: newID))
                ud.set(kind,      forKey: kindKey(for: newID))

                if let idx = ids.firstIndex(of: oldStr) { ids[idx] = newID.uuidString }
                ud.set(ids, forKey: storageKey(forStackID: stackID))

                // ✅ fixed quoting here:
                MiniDiag.log("[CHAIN] resched id=\(newID.uuidString) prev=\(oldID.uuidString) newOffset=\(String(format: "%.1fs", newOffset)) newTarget=\(newNominal) enforcedLead=\(enforcedStr) kind=\(kind) allowSnooze=\(allowSnooze)")
            } catch {
                MiniDiag.log("[CHAIN] FAILED to reschedule prev=\(oldID.uuidString) error=\(error)")
            }
        }
    }
    
    // MARK: Cleanup

    @MainActor
    private func cleanupExpectationAndMetadata(for id: UUID) {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: expectedKey(for: id))
        ud.removeObject(forKey: "ak.snoozeMinutes.\(id.uuidString)")
        ud.removeObject(forKey: "ak.stackName.\(id.uuidString)")
        ud.removeObject(forKey: "ak.stepTitle.\(id.uuidString)")
        ud.removeObject(forKey: soundKey(for: id))
        ud.removeObject(forKey: accentHexKey(for: id))
        ud.removeObject(forKey: stackIDKey(for: id))
        ud.removeObject(forKey: offsetFromFirstKey(for: id))
        ud.removeObject(forKey: kindKey(for: id))
        ud.removeObject(forKey: allowSnoozeKey(for: id))
    }
}
