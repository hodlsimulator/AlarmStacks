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
private func resolveAccentShared() -> Color {
    let groupID = AppGroups.main
    if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID),
       let ud = UserDefaults(suiteName: groupID),
       let hex = ud.string(forKey: "themeAccentHex"), !hex.isEmpty {
        print("[INTENTS] accentHex src=appGroup hex=\(hex) container=\(container.path)")
        return colorFromHex(hex)
    }
    if let hex = UserDefaults.standard.string(forKey: "themeAccentHex"), !hex.isEmpty {
        print("[INTENTS] accentHex src=standard hex=\(hex)")
        return colorFromHex(hex)
    }
    print("[INTENTS] accentHex src=fallback (default blue)")
    return Color(.sRGB, red: 0.23, green: 0.48, blue: 1.0, opacity: 1)
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
        await MainActor.run { try? AlarmManager.shared.stop(id: id) }
        return .result()
    }
}

// MARK: - Snooze

struct SnoozeAlarmIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Snooze Alarm" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID") var alarmID: String

    init() { self.alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        guard let baseID = UUID(uuidString: alarmID) else { return .result() }
        await performSnoozeOnMain(baseID: baseID)
        return .result()
    }

    @MainActor
    private func performSnoozeOnMain(baseID: UUID) async {
        SnoozeTapStore.rememberTap(for: baseID)
        try? AlarmManager.shared.stop(id: baseID)

        let ud = UserDefaults.standard
        let minutes   = max(1, ud.integer(forKey: "ak.snoozeMinutes.\(baseID.uuidString)"))
        let stackName = ud.string(forKey: "ak.stackName.\(baseID.uuidString)") ?? "Alarm"
        let stepTitle = ud.string(forKey: "ak.stepTitle.\(baseID.uuidString)") ?? "Snoozed"

        let now = Date()
        let setSecs = max(1, minutes) * 60
        var duration = TimeInterval(setSecs)
        if duration < 1 { duration = 1 }
        let effTarget = now.addingTimeInterval(duration)

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

        // Prefer per-alarm accent (App Group first), then shared, then fallback.
        let groupID = AppGroups.main
        var accent: Color? = nil
        if let udg = UserDefaults(suiteName: groupID),
           let hx = udg.string(forKey: "ak.accentHex.\(baseID.uuidString)"),
           !hx.isEmpty {
            print("[INTENTS] accentHex src=perAlarm appGroup hex=\(hx)")
            accent = colorFromHex(hx)
        } else if let hx = UserDefaults.standard.string(forKey: "ak.accentHex.\(baseID.uuidString)"), !hx.isEmpty {
            print("[INTENTS] accentHex src=perAlarm standard hex=\(hx)")
            accent = colorFromHex(hx)
        }
        let resolvedAccent = accent ?? resolveAccentShared()

        let attrs = AlarmAttributes<IntentsMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: resolvedAccent
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

        do { _ = try await AlarmManager.shared.schedule(id: id, configuration: cfg) } catch {
            print("[INTENTS] FAILED to schedule snooze: \(error)")
            return
        }

        ud.set(effTarget.timeIntervalSince1970, forKey: "ak.expected.\(id.uuidString)")
        ud.set(id.uuidString, forKey: "ak.snooze.map.\(baseID.uuidString)")
        ud.set(minutes, forKey: "ak.snoozeMinutes.\(id.uuidString)")
        ud.set(stackName, forKey: "ak.stackName.\(id.uuidString)")
        ud.set(stepTitle, forKey: "ak.stepTitle.\(id.uuidString)")

        let effStr = ISO8601DateFormatter().string(from: effTarget)
        print("[INTENTS] Snooze scheduled base=\(baseID.uuidString) id=\(id.uuidString) set=\(setSecs)s effTarget=\(effStr)")
    }
}
