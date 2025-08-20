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

// MARK: - Local helpers (self-contained; no external app-type calls)

/// Dedicated metadata type so we don't collide with the app's `EmptyMetadata`.
nonisolated struct IntentsMetadata: AlarmMetadata {}

/// Store the exact tap moment so snooze = tap + N×60s.
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
        let stamp = ISO8601DateFormatter().string(from: wall)
        print("[INTENTS] Snooze tap recorded base=\(base.uuidString) at \(stamp) up=\(up)")
    }
}

/// Hex → Color (#RRGGBB or RRGGBBAA)
private func colorFromHex(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0
    guard Scanner(string: s).scanHexInt64(&v) else { return .orange }
    switch s.count {
    case 6:
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    case 8:
        let r = Double((v >> 24) & 0xFF) / 255.0
        let g = Double((v >> 16) & 0xFF) / 255.0
        let b = Double((v >> 8) & 0xFF) / 255.0
        let a = Double(v & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    default:
        return .orange
    }
}

/// Resolve accent from the App Group (written by the main app); fall back to a sane default.
/// If you see "Cannot find 'AppGroups' in scope", add `AppGroups.swift` to the Intents target.
@MainActor
private func resolveAccentFromAppGroup() -> Color {
    if let ud = UserDefaults(suiteName: AppGroups.main),
       let hex = ud.string(forKey: "themeAccentHex") {
        return colorFromHex(hex)
    }
    return .orange
}

// MARK: - Stop

struct StopAlarmIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop Alarm" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() { self.alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        await MainActor.run { try? AlarmManager.shared.stop(id: id) }
        return .result()
    }
}

// MARK: - Snooze

struct SnoozeAlarmIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Snooze Alarm" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() { self.alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        guard let baseID = UUID(uuidString: alarmID) else { return .result() }
        await performSnoozeOnMain(baseID: baseID)
        return .result()
    }

    @MainActor
    private func performSnoozeOnMain(baseID: UUID) async {
        // 1) Stamp the tap so snooze is anchored to the press moment.
        SnoozeTapStore.rememberTap(for: baseID)

        // 2) Silence the current ring.
        try? AlarmManager.shared.stop(id: baseID)

        // 3) Read per-alarm snooze config persisted at schedule time.
        let ud = UserDefaults.standard
        let minutes   = max(1, ud.integer(forKey: "ak.snoozeMinutes.\(baseID.uuidString)"))
        let stackName = ud.string(forKey: "ak.stackName.\(baseID.uuidString)") ?? "Alarm"
        let stepTitle = ud.string(forKey: "ak.stepTitle.\(baseID.uuidString)") ?? "Snoozed"

        // 4) Compute a duration to hit (tap + N×60).
        let now     = Date()
        let upNow   = ProcessInfo.processInfo.systemUptime
        let setSecs = max(1, minutes) * 60
        let desiredTarget = now.addingTimeInterval(TimeInterval(setSecs))
        var duration = desiredTarget.timeIntervalSince(now)
        if duration < 1 { duration = 1 } // safety floor

        let effTarget = now.addingTimeInterval(duration)

        // 5) Build alert + attributes with your app's accent colour from App Group.
        let id = UUID()
        let title: LocalizedStringResource = LocalizedStringResource("\(stackName) — \(stepTitle)")

        let stopBtn   = AlarmButton(text: LocalizedStringResource("Stop"),   textColor: .white, systemImageName: "stop.fill")
        let snoozeBtn = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: stopBtn,
            secondaryButton: snoozeBtn,
            secondaryButtonBehavior: .countdown
        )

        let attrs = AlarmAttributes<IntentsMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: resolveAccentFromAppGroup()
        )

        let stopI   = StopAlarmIntent(alarmID: id.uuidString)
        let snoozeI = SnoozeAlarmIntent(alarmID: id.uuidString)

        let cfg: AlarmManager.AlarmConfiguration<IntentsMetadata> = .timer(
            duration: duration,
            attributes: attrs,
            stopIntent: stopI,
            secondaryIntent: snoozeI,
            sound: AlertConfiguration.AlertSound.default
        )

        do { _ = try await AlarmManager.shared.schedule(id: id, configuration: cfg) }
        catch {
            print("[INTENTS] FAILED to schedule snooze: \(error)")
            return
        }

        // 6) Persist expectations + mapping for diagnostics.
        ud.set(effTarget.timeIntervalSince1970, forKey: "ak.expected.\(id.uuidString)")
        ud.set(id.uuidString, forKey: "ak.snooze.map.\(baseID.uuidString)")
        ud.set(minutes, forKey: "ak.snoozeMinutes.\(id.uuidString)")
        ud.set(stackName, forKey: "ak.stackName.\(id.uuidString)")
        ud.set(stepTitle, forKey: "ak.stepTitle.\(id.uuidString)")

        // Clean logging
        let desiredStr = ISO8601DateFormatter().string(from: desiredTarget)
        let effStr     = ISO8601DateFormatter().string(from: effTarget)
        let durStr     = String(format: "%.3f", duration)
        let upStr      = String(format: "%.3f", upNow)
        print("[INTENTS] Snooze scheduled base=\(baseID.uuidString) id=\(id.uuidString) set=\(setSecs)s dur=\(durStr)s desired=\(desiredStr) effTarget=\(effStr) upNow=\(upStr)")
    }
}
        