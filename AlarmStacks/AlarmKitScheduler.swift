//
//  AlarmKitScheduler.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

#if canImport(AlarmKit)

import Foundation
import SwiftData
import SwiftUI
import AlarmKit
import ActivityKit
import AppIntents
import os.log
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AlarmKitScheduler: ChainAlarmSchedulingAdapter {
    static let shared = AlarmKitScheduler()

    let manager  = AlarmManager.shared
    let defaults = UserDefaults.standard
    let log      = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AlarmKit")
    let groupDefaults = UserDefaults(suiteName: AppGroups.main)

    // MARK: Tunables
    static let minLeadSecondsFirst  = 60
    static let minLeadSecondsNormal = 60
    static let protectedWindowSecs  = 12
    static let postAuthSettleMs: UInt64 = 800

    private static let defaultSoundFilename: String? = nil

    private var hasScheduledOnceAK: Bool {
        get { defaults.bool(forKey: "ak.hasScheduledOnce") }
        set { defaults.set(newValue, forKey: "ak.hasScheduledOnce") }
    }

    private init() {}

    // Keys
    func storageKey(for stack: Stack) -> String { "alarmkit.ids.\(stack.id.uuidString)" }
    func storageKey(forStackID stackID: String) -> String { "alarmkit.ids.\(stackID)" }
    func expectedKey(for id: UUID) -> String { "ak.expected.\(id.uuidString)" }
    func snoozeMapKey(for base: UUID) -> String { "ak.snooze.map.\(base.uuidString)" }
    func soundKey(for id: UUID) -> String { "ak.soundName.\(id.uuidString)" }
    func accentHexKey(for id: UUID) -> String { "ak.accentHex.\(id.uuidString)" }

    func stackIDKey(for id: UUID) -> String { "ak.stackID.\(id.uuidString)" }
    func offsetFromFirstKey(for id: UUID) -> String { "ak.offsetFromFirst.\(id.uuidString)" }
    func firstTargetKey(forStackID id: String) -> String { "ak.firstTarget.\(id)" }
    func kindKey(for id: UUID) -> String { "ak.kind.\(id.uuidString)" }
    func allowSnoozeKey(for id: UUID) -> String { "ak.allowSnooze.\(id.uuidString)" }

    // Effective target (timer) key — used for snooze/test timers ONLY
    func effTargetKey(for id: UUID) -> String { "ak.effTarget.\(id.uuidString)" }

    // MARK: - Colour helpers

    func colorFromHex(_ hex: String) -> SwiftUI.Color {
        #if canImport(UIKit)
        let ui: UIColor = {
            var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if s.hasPrefix("#") { s.removeFirst() }
            var v: UInt64 = 0
            guard Scanner(string: s).scanHexInt64(&v) else {
                return UIColor(red: 0.23, green: 0.48, blue: 1.00, alpha: 1.0)
            }
            switch s.count {
            case 6:
                let r = CGFloat((v >> 16) & 0xFF) / 255.0
                let g = CGFloat((v >>  8) & 0xFF) / 255.0
                let b = CGFloat( v        & 0xFF) / 255.0
                return UIColor(red: r, green: g, blue: b, alpha: 1.0)
            case 8:
                let r = CGFloat((v >> 24) & 0xFF) / 255.0
                let g = CGFloat((v >> 16) & 0xFF) / 255.0
                let b = CGFloat((v >>  8) & 0xFF) / 255.0
                let a = CGFloat( v        & 0xFF) / 255.0
                return UIColor(red: r, green: g, blue: b, alpha: a)
            default:
                return UIColor(red: 0.23, green: 0.48, blue: 1.00, alpha: 1.0)
            }
        }()
        return SwiftUI.Color(uiColor: ui)
        #else
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&v) else {
            return SwiftUI.Color(red: 0.23, green: 0.48, blue: 1.00, opacity: 1.0)
        }
        switch s.count {
        case 6:
            let r = Double((v >> 16) & 0xFF) / 255.0
            let g = Double((v >>  8) & 0xFF) / 255.0
            let b = Double( v        & 0xFF) / 255.0
            return SwiftUI.Color(red: r, green: g, blue: b, opacity: 1.0)
        case 8:
            let r = Double((v >> 24) & 0xFF) / 255.0
            let g = Double((v >> 16) & 0xFF) / 255.0
            let b = Double((v >>  8) & 0xFF) / 255.0
            let a = Double( v        & 0xFF) / 255.0
            return SwiftUI.Color(red: r, green: g, blue: b, opacity: a)
        default:
            return SwiftUI.Color(red: 0.23, green: 0.48, blue: 1.00, opacity: 1.0)
        }
        #endif
    }

    #if canImport(UIKit)
    private func hex(from color: SwiftUI.Color) -> String? {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let R = Int(round(r * 255))
        let G = Int(round(g * 255))
        let B = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", R, G, B)
    }
    #endif

    // MARK: - Permissions

    func requestAuthorizationIfNeeded() async throws {
        switch manager.authorizationState {
        case .authorized: return
        case .denied:
            throw NSError(domain: "AlarmStacks", code: 1001,
                          userInfo: [NSLocalizedDescriptionKey: "Alarm permission denied"])
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            guard state == .authorized else {
                throw NSError(domain: "AlarmStacks", code: 1002,
                              userInfo: [NSLocalizedDescriptionKey: "Alarm permission not granted"])
            }
        @unknown default:
            throw NSError(domain: "AlarmStacks", code: 1003,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown AlarmKit authorisation state"])
        }
    }

    // MARK: - Scheduling (initial, per stack)

    @MainActor
    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        try await requestAuthorizationIfNeeded()

        // If something is about to fire within the protected window, keep current schedules
        // but make sure the Live Activity shows the actual pending target.
        if let imminent = nextEnabledStepFireDate(for: stack, calendar: calendar),
           imminent.timeIntervalSinceNow <= TimeInterval(Self.protectedWindowSecs) {
            DiagLog.log("AK schedule SKIP (protected window) next=\(DiagLog.f(imminent)) (~\(Int(imminent.timeIntervalSinceNow))s)")
            LiveActivityManager.start(stackID: stack.id.uuidString, calendar: calendar)
            return defaults.stringArray(forKey: storageKey(for: stack)) ?? []
        }

        if hasScheduledOnceAK == false {
            try? await Task.sleep(nanoseconds: Self.postAuthSettleMs * 1_000_000)
        }

        // Clear out old schedules before laying down the new plan.
        await cancelAll(for: stack)

        var lastFireDate = Date()
        var akIDs: [UUID] = []

        let firstRun = (hasScheduledOnceAK == false)
        let minLead  = firstRun ? Self.minLeadSecondsFirst : Self.minLeadSecondsNormal

        if let eff = effectiveLeadSeconds(for: stack, calendar: calendar, minLead: minLead) {
            DiagLog.log("AK decision ctx: firstRun=\(firstRun) minLeadPref=0s effFirst=\(eff)s")
        } else {
            DiagLog.log("AK decision ctx: firstRun=\(firstRun) (no enabled steps)")
        }

        // Resolve the active accent once for this pass and export for intents/widget.
        let tintNow = ThemeTintResolver.currentAccent()
        #if canImport(UIKit)
        if let hexNow = hex(from: tintNow) {
            defaults.set(hexNow, forKey: "themeAccentHex")
            groupDefaults?.set(hexNow, forKey: "themeAccentHex")
        }
        #endif

        // Track first enabled step’s nominal for offsets.
        var firstNominal: Date?

        for step in stack.sortedSteps where step.isEnabled {
            let nominalFireDate: Date
            switch step.kind {
            case .fixedTime:
                nominalFireDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
                lastFireDate = nominalFireDate
            case .timer, .relativeToPrev:
                nominalFireDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
                lastFireDate = nominalFireDate
            }

            if firstNominal == nil {
                firstNominal = nominalFireDate
                defaults.set(nominalFireDate.timeIntervalSince1970, forKey: firstTargetKey(forStackID: stack.id.uuidString))
            }

            // Effective ≥ minLead from now.
            let now = Date()
            let rawLead = max(0, nominalFireDate.timeIntervalSince(now))
            let seconds = max(minLead, Int(ceil(rawLead)))
            let effectiveTarget = now.addingTimeInterval(TimeInterval(seconds))

            let id = UUID()

            let title: LocalizedStringResource = LocalizedStringResource("\(stack.name) — \(step.title)")
            let alert = makeAlert(title: title, allowSnooze: step.allowSnooze)
            let attrs  = makeAttributes(alert: alert, tint: tintNow)
            let sound  = resolveSound(forStepName: step.soundName)

            let stopI   = StopAlarmIntent(alarmID: id.uuidString)
            let snoozeI = step.allowSnooze ? SnoozeAlarmIntent(alarmID: id.uuidString) : nil

            let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                duration: TimeInterval(seconds),
                attributes: attrs,
                stopIntent: stopI,
                secondaryIntent: snoozeI,
                sound: sound
            )

            log.info("AK schedule id=\(id.uuidString, privacy: .public) secs=\(seconds, privacy: .public) eff=\(effectiveTarget as NSDate, privacy: .public) nominal=\(nominalFireDate as NSDate, privacy: .public) stack=\(stack.name, privacy: .public) step=\(step.title, privacy: .public)")
            DiagLog.log("AK schedule id=\(id.uuidString) secs=\(seconds)s effTarget=\(DiagLog.f(effectiveTarget)) nominal=\(DiagLog.f(nominalFireDate)); stack=\(stack.name); step=\(step.title)")

            // Persist metadata (LA reads from App Group / defaults)
            defaults.set(effectiveTarget.timeIntervalSince1970, forKey: effTargetKey(for: id))

            if let n = step.soundName, !n.isEmpty { defaults.set(n, forKey: soundKey(for: id)) }
            else if let n = Self.defaultSoundFilename { defaults.set(n, forKey: soundKey(for: id)) }
            defaults.set(step.snoozeMinutes, forKey: "ak.snoozeMinutes.\(id.uuidString)")
            defaults.set(stack.name,        forKey: "ak.stackName.\(id.uuidString)")
            defaults.set(step.title,        forKey: "ak.stepTitle.\(id.uuidString)")
            defaults.set(step.allowSnooze,  forKey: allowSnoozeKey(for: id))

            #if canImport(UIKit)
            if let hx = hex(from: tintNow) {
                defaults.set(hx, forKey: accentHexKey(for: id))
                groupDefaults?.set(hx, forKey: accentHexKey(for: id))
            }
            #endif

            defaults.set(stack.id.uuidString, forKey: stackIDKey(for: id))
            if let f = firstNominal {
                let off = nominalFireDate.timeIntervalSince(f)
                defaults.set(off, forKey: offsetFromFirstKey(for: id))
            } else {
                defaults.set(0.0, forKey: offsetFromFirstKey(for: id))
            }
            defaults.set(kindLabel(for: step.kind), forKey: kindKey(for: id))

            _ = try await manager.schedule(id: id, configuration: cfg)

            // (Optional diagnostic)
            AKDiag.save(
                id: id,
                record: AKDiag.Record(
                    stackName: stack.name,
                    stepTitle: step.title,
                    scheduledAt: now,
                    scheduledUptime: ProcessInfo.processInfo.systemUptime,
                    targetDate: effectiveTarget,
                    targetUptime: ProcessInfo.processInfo.systemUptime + TimeInterval(seconds),
                    seconds: seconds,
                    kind: .step,
                    baseID: nil,
                    isFirstRun: firstRun,
                    minLeadSeconds: minLead,
                    allowSnooze: step.allowSnooze,
                    soundName: step.soundName,
                    snoozeMinutes: step.snoozeMinutes,
                    build: nil,
                    source: "schedule(stack:)",
                    nominalDate: nominalFireDate,
                    nominalSource: "step.nextFireDate"
                )
            )

            akIDs.append(id)
        }

        if firstRun { hasScheduledOnceAK = true }
        defaults.set(akIDs.map(\.uuidString), forKey: storageKey(for: stack))

        // ✅ Confirm/update LA **after** scheduling so it picks up the near-term effective targets.
        LiveActivityManager.start(stackID: stack.id.uuidString, calendar: calendar)

        // 🔔 SINGLE place to signal chain change to widget + logs
        ScheduleRevision.bump("chainShift")

        return akIDs.map(\.uuidString)
    }

    func cancelAll(for stack: Stack) async {
        let key = storageKey(for: stack)
        for s in (defaults.stringArray(forKey: key) ?? []) {
            if let id = UUID(uuidString: s) {
                try? manager.cancel(id: id)
                cleanupExpectationAndMetadata(for: id)
            }
        }
        defaults.removeObject(forKey: key)
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        for s in stacks where s.isArmed { _ = try? await schedule(stack: s, calendar: calendar) }
    }

    // MARK: - ChainAlarmSchedulingAdapter (used by ChainSnoozeCoordinator)

    func cancelAlarm(id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        try? manager.cancel(id: uuid)
    }

    func scheduleAlarm(id: String, epochSeconds: Int, soundName: String?, accentHex: String?, allowSnooze: Bool) {
        guard let uuid = UUID(uuidString: id) else { return }

        let nowEpoch = Int(Date().timeIntervalSince1970)
        let seconds = max(1, epochSeconds - nowEpoch)
        let target  = Date(timeIntervalSince1970: TimeInterval(nowEpoch + seconds))

        let stackName = defaults.string(forKey: "ak.stackName.\(uuid.uuidString)") ?? "Alarm"
        let stepTitle = defaults.string(forKey: "ak.stepTitle.\(uuid.uuidString)") ?? "Step"

        let tint: SwiftUI.Color = {
            if let hx = accentHex, !hx.isEmpty { return colorFromHex(hx) }
            if let hx = defaults.string(forKey: accentHexKey(for: uuid)), !hx.isEmpty { return colorFromHex(hx) }
            if let hx = defaults.string(forKey: "themeAccentHex"), !hx.isEmpty { return colorFromHex(hx) }
            return ThemeTintResolver.currentAccent()
        }()

        let alert = makeAlert(title: LocalizedStringResource("\(stackName) — \(stepTitle)"), allowSnooze: allowSnooze)
        let attrs = makeAttributes(alert: alert, tint: tint)
        let sound = resolveSound(forStepName: soundName)

        let stopI   = StopAlarmIntent(alarmID: uuid.uuidString)
        let snoozeI = allowSnooze ? SnoozeAlarmIntent(alarmID: uuid.uuidString) : nil

        Task { @MainActor in
            do {
                let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                    duration: TimeInterval(seconds),
                    attributes: attrs,
                    stopIntent: stopI,
                    secondaryIntent: snoozeI,
                    sound: sound
                )
                _ = try await manager.schedule(id: uuid, configuration: cfg)

                defaults.set(target.timeIntervalSince1970, forKey: effTargetKey(for: uuid))

                AKDiag.save(
                    id: uuid,
                    record: AKDiag.Record(
                        stackName: stackName,
                        stepTitle: stepTitle,
                        scheduledAt: Date(),
                        scheduledUptime: ProcessInfo.processInfo.systemUptime,
                        targetDate: target,
                        targetUptime: ProcessInfo.processInfo.systemUptime + TimeInterval(seconds),
                        seconds: seconds,
                        kind: .step,
                        baseID: nil,
                        isFirstRun: nil,
                        minLeadSeconds: Self.minLeadSecondsNormal,
                        allowSnooze: allowSnooze,
                        soundName: soundName,
                        snoozeMinutes: defaults.integer(forKey: "ak.snoozeMinutes.\(uuid.uuidString)"),
                        build: nil,
                        source: "adapter.scheduleAlarm",
                        nominalDate: nil,
                        nominalSource: nil
                    )
                )

                DiagLog.log("[AK] adapter schedule id=\(uuid.uuidString) secs=\(seconds)s effTarget=\(DiagLog.f(target)) allowSnooze=\(allowSnooze)")

                // 🔔 Inform widget about this ad-hoc schedule
                ScheduleRevision.bump("adapterSchedule")
            } catch {
                DiagLog.log("[AK] adapter schedule FAILED id=\(uuid.uuidString) error=\(error)")
            }
        }
    }

    // MARK: Helpers

    private func nextEnabledStepFireDate(for stack: Stack, calendar: Calendar) -> Date? {
        let base = Date()
        for step in stack.sortedSteps where step.isEnabled {
            switch step.kind {
            case .fixedTime:
                if let d = try? step.nextFireDate(basedOn: Date(), calendar: calendar) { return d }
                else { return nil }
            case .timer, .relativeToPrev:
                if let d = try? step.nextFireDate(basedOn: base, calendar: calendar) { return d }
                else { return nil }
            }
        }
        return nil
    }

    private func effectiveLeadSeconds(for stack: Stack, calendar: Calendar, minLead: Int) -> Int? {
        var probeBase = Date()
        for step in stack.sortedSteps where step.isEnabled {
            let fireDate: Date
            switch step.kind {
            case .fixedTime:
                fireDate = (try? step.nextFireDate(basedOn: Date(), calendar: calendar)) ?? Date().addingTimeInterval(3600)
                probeBase = fireDate
            case .timer, .relativeToPrev:
                fireDate = (try? step.nextFireDate(basedOn: probeBase, calendar: calendar)) ?? Date().addingTimeInterval(3600)
                probeBase = fireDate
            }
            let raw = max(0, fireDate.timeIntervalSinceNow)
            return max(minLead, Int(ceil(raw)))
        }
        return nil
    }

    private func cleanupExpectationAndMetadata(for id: UUID) {
        defaults.removeObject(forKey: effTargetKey(for: id))
        defaults.removeObject(forKey: "ak.snoozeMinutes.\(id.uuidString)")
        defaults.removeObject(forKey: "ak.stackName.\(id.uuidString)")
        defaults.removeObject(forKey: "ak.stepTitle.\(id.uuidString)")
        defaults.removeObject(forKey: soundKey(for: id))
        defaults.removeObject(forKey: accentHexKey(for: id))
        defaults.removeObject(forKey: stackIDKey(for: id))
        defaults.removeObject(forKey: offsetFromFirstKey(for: id))
        defaults.removeObject(forKey: kindKey(for: id))
        defaults.removeObject(forKey: allowSnoozeKey(for: id))
        groupDefaults?.removeObject(forKey: accentHexKey(for: id))
    }

    private func resolveSound(forStepName name: String?) -> AlertConfiguration.AlertSound {
        // We only use AK alarms; no UN banners/sounds.
        .default
    }

    private func kindLabel(for kind: StepKind) -> String {
        switch kind {
        case .fixedTime:       return "fixed"
        case .timer:           return "timer"
        case .relativeToPrev:  return "relative"
        }
    }
}

// MARK: - AlarmKit helpers

nonisolated struct EmptyMetadata: AlarmMetadata {}

private func makeAlert(title: LocalizedStringResource, allowSnooze: Bool) -> AlarmPresentation.Alert {
    let stop = AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
    if allowSnooze {
        let snooze = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
        return AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: snooze, secondaryButtonBehavior: .countdown)
    } else {
        return AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: nil, secondaryButtonBehavior: nil)
    }
}

private func makeAttributes(alert: AlarmPresentation.Alert, tint: SwiftUI.Color) -> AlarmAttributes<EmptyMetadata> {
    let presentation = AlarmPresentation(alert: alert)
    return AlarmAttributes<EmptyMetadata>(
        presentation: presentation,
        tintColor: tint
    )
}

#endif
