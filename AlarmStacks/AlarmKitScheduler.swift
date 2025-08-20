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
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    private let manager  = AlarmManager.shared
    private let defaults = UserDefaults.standard
    private let log      = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AlarmKit")
    private let groupDefaults = UserDefaults(suiteName: AppGroups.main)

    // MARK: Tunables
    private static let minLeadSecondsFirst  = 60
    private static let minLeadSecondsNormal = 60
    private static let protectedWindowSecs  = 12
    private static let postAuthSettleMs: UInt64 = 800

    private static let defaultSoundFilename: String? = nil

    private var hasScheduledOnceAK: Bool {
        get { defaults.bool(forKey: "ak.hasScheduledOnce") }
        set { defaults.set(newValue, forKey: "ak.hasScheduledOnce") }
    }

    private init() {}

    // Existing keys
    private func storageKey(for stack: Stack) -> String { "alarmkit.ids.\(stack.id.uuidString)" }
    private func storageKey(forStackID stackID: String) -> String { "alarmkit.ids.\(stackID)" }
    private func expectedKey(for id: UUID) -> String { "ak.expected.\(id.uuidString)" }
    private func snoozeMapKey(for base: UUID) -> String { "ak.snooze.map.\(base.uuidString)" }
    private func soundKey(for id: UUID) -> String { "ak.soundName.\(id.uuidString)" }
    private func accentHexKey(for id: UUID) -> String { "ak.accentHex.\(id.uuidString)" }

    // NEW: mapping for chained shift
    private func stackIDKey(for id: UUID) -> String { "ak.stackID.\(id.uuidString)" }
    private func offsetFromFirstKey(for id: UUID) -> String { "ak.offsetFromFirst.\(id.uuidString)" }
    private func firstTargetKey(forStackID id: String) -> String { "ak.firstTarget.\(id)" }
    private func kindKey(for id: UUID) -> String { "ak.kind.\(id.uuidString)" }
    private func allowSnoozeKey(for id: UUID) -> String { "ak.allowSnooze.\(id.uuidString)" }

    // MARK: - Colour helpers

    /// Convert a hex string to SwiftUI.Color by first constructing a fully-labelled UIColor.
    private func colorFromHex(_ hex: String) -> SwiftUI.Color {
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
        return String(format: "#%02X%02X%02X", R, G, B) // alpha intentionally ignored
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

    // MARK: - Scheduling (single AK timer per step) WITH AppIntents actions

    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        try await requestAuthorizationIfNeeded()

        if let imminent = nextEnabledStepFireDate(for: stack, calendar: calendar),
           imminent.timeIntervalSinceNow <= TimeInterval(Self.protectedWindowSecs) {
            DiagLog.log("AK schedule SKIP (protected window) next=\(DiagLog.f(imminent)) (~\(Int(imminent.timeIntervalSinceNow))s)")
            return defaults.stringArray(forKey: storageKey(for: stack)) ?? []
        }

        if hasScheduledOnceAK == false {
            try? await Task.sleep(nanoseconds: Self.postAuthSettleMs * 1_000_000)
        }

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

        // Resolve the active accent ONCE for this scheduling pass.
        let tintNow = ThemeTintResolver.currentAccent()
        #if canImport(UIKit)
        if let hexNow = hex(from: tintNow) {
            defaults.set(hexNow, forKey: "themeAccentHex")
            groupDefaults?.set(hexNow, forKey: "themeAccentHex")
        }
        #endif

        // Track the first enabled step's nominal target for offset persistence.
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

            // Effective schedule is at least minLead from NOW.
            let now = Date()
            let rawLead = max(0, nominalFireDate.timeIntervalSince(now))
            let seconds = max(minLead, Int(ceil(rawLead)))
            let effectiveTarget = now.addingTimeInterval(TimeInterval(seconds))

            let id = UUID()

            let title: LocalizedStringResource = LocalizedStringResource("\(stack.name) — \(step.title)")
            let alert = makeAlert(title: title, allowSnooze: step.allowSnooze)
            let attrs  = makeAttributes(alert: alert, tint: tintNow)
            let sound  = resolveSound(forStepName: step.soundName)

            // Attach AppIntent actions so Snooze goes through our unified path.
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

            // Persist expectation **nominal** (calendar) for compatibility with previous diagnostics,
            // and keep full effective vs nominal in AKDiag.
            defaults.set(nominalFireDate.timeIntervalSince1970, forKey: expectedKey(for: id))

            if let n = step.soundName, !n.isEmpty { defaults.set(n, forKey: soundKey(for: id)) }
            else if let n = Self.defaultSoundFilename { defaults.set(n, forKey: soundKey(for: id)) }
            defaults.set(step.snoozeMinutes, forKey: "ak.snoozeMinutes.\(id.uuidString)")
            defaults.set(stack.name,        forKey: "ak.stackName.\(id.uuidString)")
            defaults.set(step.title,        forKey: "ak.stepTitle.\(id.uuidString)")
            defaults.set(step.allowSnooze,  forKey: allowSnoozeKey(for: id))

            // Persist per-id accent (std + app group)
            #if canImport(UIKit)
            if let hx = hex(from: tintNow) {
                defaults.set(hx, forKey: accentHexKey(for: id))
                groupDefaults?.set(hx, forKey: accentHexKey(for: id))
            }
            #endif

            // Persist stackID + offset-from-first + kind label for later chain shifts
            defaults.set(stack.id.uuidString, forKey: stackIDKey(for: id))
            if let f = firstNominal {
                let off = nominalFireDate.timeIntervalSince(f)
                defaults.set(off, forKey: offsetFromFirstKey(for: id))
            } else {
                defaults.set(0.0, forKey: offsetFromFirstKey(for: id))
            }
            defaults.set(kindLabel(for: step.kind), forKey: kindKey(for: id))

            _ = try await manager.schedule(id: id, configuration: cfg)

            AKDiag.save(
                id: id,
                record: AKDiag.Record(
                    stackName: stack.name,
                    stepTitle: step.title,
                    scheduledAt: now,
                    scheduledUptime: ProcessInfo.processInfo.systemUptime,
                    targetDate: effectiveTarget, // effective
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

        await LiveActivityManager.start(for: stack, calendar: calendar)
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

    // MARK: - AlarmKit Snooze (timer-based; AK-only, unified path)

    /// Schedules a precise AlarmKit timer as a snooze for `minutes` from now.
    /// If the base belongs to the first step of its stack, push the chain by the same delta.
    @discardableResult
    func scheduleSnooze(
        baseAlarmID: UUID,
        stackName: String,
        stepTitle: String,
        minutes: Int
    ) async -> String? {
        // Cancel existing snooze for this base alarm, if any.
        if let existing = defaults.string(forKey: snoozeMapKey(for: baseAlarmID)),
           let existingID = UUID(uuidString: existing) {
            try? manager.cancel(id: existingID)
            cleanupExpectationAndMetadata(for: existingID)
            defaults.removeObject(forKey: snoozeMapKey(for: baseAlarmID))
        }

        let id = UUID()
        let seconds = max(Self.minLeadSecondsNormal, minutes * 60)
        let target = Date().addingTimeInterval(TimeInterval(seconds))

        let title: LocalizedStringResource = LocalizedStringResource("\(stackName) — \(stepTitle)")
        let alert = makeAlert(title: title, allowSnooze: true)

        // Prefer the EXACT accent used by the base alarm (App Group first)
        let carriedGroup = groupDefaults?.string(forKey: accentHexKey(for: baseAlarmID))
        let carriedStd   = defaults.string(forKey: accentHexKey(for: baseAlarmID))
        let tint: SwiftUI.Color
        if let hx = carriedGroup, !hx.isEmpty {
            tint = colorFromHex(hx)
        } else if let hx = carriedStd, !hx.isEmpty {
            tint = colorFromHex(hx)
        } else {
            tint = ThemeTintResolver.currentAccent()
        }
        let attrs = makeAttributes(alert: alert, tint: tint)

        let carriedName = defaults.string(forKey: soundKey(for: baseAlarmID))
        let sound = resolveSound(forStepName: carriedName)

        // Attach intents to the snooze alarm as well.
        let stopI   = StopAlarmIntent(alarmID: id.uuidString)
        let snoozeI = SnoozeAlarmIntent(alarmID: id.uuidString)

        do {
            let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                duration: TimeInterval(seconds),
                attributes: attrs,
                stopIntent: stopI,
                secondaryIntent: snoozeI,
                sound: sound
            )
            _ = try await manager.schedule(id: id, configuration: cfg)

            // Persist diagnostics + mapping for chained snoozes.
            defaults.set(target.timeIntervalSince1970, forKey: expectedKey(for: id)) // store eff target for snooze
            defaults.set(id.uuidString, forKey: snoozeMapKey(for: baseAlarmID))
            defaults.set(minutes, forKey: "ak.snoozeMinutes.\(id.uuidString)")
            defaults.set(stackName, forKey: "ak.stackName.\(id.uuidString)")
            defaults.set(stepTitle, forKey: "ak.stepTitle.\(id.uuidString)")
            if let n = carriedName, !n.isEmpty { defaults.set(n, forKey: soundKey(for: id)) }

            // Persist accent for the NEW snooze id (std + group)
            #if canImport(UIKit)
            if let hx = hex(from: tint) {
                defaults.set(hx, forKey: accentHexKey(for: id))
                groupDefaults?.set(hx, forKey: accentHexKey(for: id))
                groupDefaults?.set(hx, forKey: "themeAccentHex")
            }
            #endif

            DiagLog.log("AK snooze schedule base=\(baseAlarmID.uuidString) id=\(id.uuidString) timer in \(seconds)s; effTarget=\(DiagLog.f(target))")

            // If this was the FIRST step of its stack, push the chain.
            await shiftChainIfFirstWasSnoozed(baseAlarmID: baseAlarmID, newBase: target)

            return id.uuidString
        } catch {
            DiagLog.log("AK snooze schedule FAILED base=\(baseAlarmID.uuidString) error=\(error)")
            return nil
        }
    }

    /// Cancels the active snooze (if any) tied to a base alarm.
    func cancelSnooze(for baseAlarmID: UUID) {
        if let existing = defaults.string(forKey: snoozeMapKey(for: baseAlarmID)),
           let existingID = UUID(uuidString: existing) {
            try? manager.cancel(id: existingID)
            cleanupExpectationAndMetadata(for: existingID)
            defaults.removeObject(forKey: snoozeMapKey(for: baseAlarmID))
            DiagLog.log("AK snooze cancel base=\(baseAlarmID.uuidString) id=\(existingID.uuidString)")
        }
    }

    // MARK: - Chain shift after snooze of first step

    private func kindLabel(for kind: StepKind) -> String {
        switch kind {
        case .fixedTime:       return "fixed"
        case .timer:           return "timer"
        case .relativeToPrev:  return "relative"
        }
    }

    private func enforceMinLeadSeconds(for nominalTarget: Date, minLead: Int) -> (seconds: Int, effectiveTarget: Date, enforced: Int?) {
        let now = Date()
        let raw = max(0, nominalTarget.timeIntervalSince(now))
        let secs = max(minLead, Int(ceil(raw)))
        let eff = now.addingTimeInterval(TimeInterval(secs))
        let enforced = secs > Int(ceil(raw)) ? secs : nil
        return (secs, eff, enforced)
    }

    /// If the snoozed base alarm was the first step of its stack, push remaining steps by the same delta.
    private func shiftChainIfFirstWasSnoozed(baseAlarmID: UUID, newBase: Date) async {
        let baseOffset = defaults.object(forKey: offsetFromFirstKey(for: baseAlarmID)) as? Double ?? Double.nan
        guard let stackID = defaults.string(forKey: stackIDKey(for: baseAlarmID)) else {
            DiagLog.log("[CHAIN] shift? base=\(baseAlarmID.uuidString) (no stackID found)")
            return
        }

        let firstEpoch = defaults.double(forKey: firstTargetKey(forStackID: stackID))
        let oldFirst = firstEpoch > 0 ? Date(timeIntervalSince1970: firstEpoch) : nil
        let delta = oldFirst.map { newBase.timeIntervalSince($0) } ?? 0
        DiagLog.log(String(format: "[CHAIN] shift? stack=%@ base=%@ first=%@ Δ=%+.3fs offsetBase=%@",
                           stackID, baseAlarmID.uuidString, oldFirst.map(DiagLog.f) ?? "nil", delta,
                           baseOffset.isNaN ? "nil" : String(format: "%.1fs", baseOffset)))

        // Only if snoozed alarm had offset==0 (first step)
        guard baseOffset.isFinite, baseOffset == 0 else { return }

        var ids = defaults.stringArray(forKey: storageKey(forStackID: stackID)) ?? []
        if ids.isEmpty {
            DiagLog.log("[CHAIN] no tracked IDs for stack=\(stackID); abort shift")
            return
        }

        // Update first target to the snooze's effective target
        defaults.set(newBase.timeIntervalSince1970, forKey: firstTargetKey(forStackID: stackID))
        DiagLog.log("[CHAIN] shift stack=\(stackID) base=\(baseAlarmID.uuidString) newBase=\(DiagLog.f(newBase))")

        for oldStr in ids {
            guard let oldID = UUID(uuidString: oldStr), oldID != baseAlarmID else { continue }

            let kind = defaults.string(forKey: kindKey(for: oldID)) ?? "timer"
            if kind == "fixed" {
                DiagLog.log("[CHAIN] skip fixed id=\(oldID.uuidString)")
                continue
            }

            guard let offset = defaults.object(forKey: offsetFromFirstKey(for: oldID)) as? Double else {
                DiagLog.log("[CHAIN] skip id=\(oldID.uuidString) (no offset)")
                continue
            }

            // Skip if we no longer track a nominal expected time (already fired/stopped).
            let expectedTS = defaults.double(forKey: expectedKey(for: oldID))
            if expectedTS <= 0 {
                DiagLog.log("[CHAIN] skip id=\(oldID.uuidString) (no expected nominal; likely fired/stopped)")
                continue
            }

            // Read carried metadata BEFORE cleanup/cancel.
            let stackName   = defaults.string(forKey: "ak.stackName.\(oldID.uuidString)") ?? "Alarm"
            let stepTitle   = defaults.string(forKey: "ak.stepTitle.\(oldID.uuidString)") ?? "Step"
            let allowSnooze = (defaults.object(forKey: allowSnoozeKey(for: oldID)) as? Bool) ?? true
            let snoozeMins  = defaults.integer(forKey: "ak.snoozeMinutes.\(oldID.uuidString)")
            let carriedName = defaults.string(forKey: soundKey(for: oldID))
            let carriedGroupHex = groupDefaults?.string(forKey: accentHexKey(for: oldID))
            let carriedStdHex   = defaults.string(forKey: accentHexKey(for: oldID))
            let tint: SwiftUI.Color = {
                if let hx = carriedGroupHex, !hx.isEmpty { return colorFromHex(hx) }
                if let hx = carriedStdHex,   !hx.isEmpty { return colorFromHex(hx) }
                return ThemeTintResolver.currentAccent()
            }()

            // Compute new target
            let newNominal = newBase.addingTimeInterval(offset)
            let (secs, effTarget, enforced) = enforceMinLeadSeconds(for: newNominal, minLead: Self.minLeadSecondsNormal)

            // Cancel old + cleanup
            try? manager.cancel(id: oldID)
            cleanupExpectationAndMetadata(for: oldID)

            // Schedule replacement
            let newID = UUID()
            let title: LocalizedStringResource = LocalizedStringResource("\(stackName) — \(stepTitle)")
            let alert = makeAlert(title: title, allowSnooze: allowSnooze)
            let attrs = makeAttributes(alert: alert, tint: tint)
            let sound = resolveSound(forStepName: carriedName)

            let stopI   = StopAlarmIntent(alarmID: newID.uuidString)
            let snoozeI = allowSnooze ? SnoozeAlarmIntent(alarmID: newID.uuidString) : nil

            do {
                let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                    duration: TimeInterval(secs),
                    attributes: attrs,
                    stopIntent: stopI,
                    secondaryIntent: snoozeI,
                    sound: sound
                )
                _ = try await manager.schedule(id: newID, configuration: cfg)

                // Persist new id’s metadata
                defaults.set(newNominal.timeIntervalSince1970, forKey: expectedKey(for: newID)) // store nominal for steps
                defaults.set(stackName,  forKey: "ak.stackName.\(newID.uuidString)")
                defaults.set(stepTitle,  forKey: "ak.stepTitle.\(newID.uuidString)")
                defaults.set(allowSnooze, forKey: allowSnoozeKey(for: newID))
                defaults.set(snoozeMins, forKey: "ak.snoozeMinutes.\(newID.uuidString)")
                if let n = carriedName, !n.isEmpty { defaults.set(n, forKey: soundKey(for: newID)) }

                #if canImport(UIKit)
                if let hx = carriedGroupHex ?? carriedStdHex {
                    defaults.set(hx, forKey: accentHexKey(for: newID))
                    groupDefaults?.set(hx, forKey: accentHexKey(for: newID))
                }
                #endif

                // Preserve mapping info for future shifts
                defaults.set(stackID, forKey: stackIDKey(for: newID))
                defaults.set(offset,  forKey: offsetFromFirstKey(for: newID))
                defaults.set(kind,    forKey: kindKey(for: newID))

                // Update tracked list
                if let idx = ids.firstIndex(of: oldStr) { ids[idx] = newID.uuidString }
                defaults.set(ids, forKey: storageKey(forStackID: stackID))

                // Diagnostics
                AKDiag.save(
                    id: newID,
                    record: AKDiag.Record(
                        stackName: stackName,
                        stepTitle: stepTitle,
                        scheduledAt: Date(),
                        scheduledUptime: ProcessInfo.processInfo.systemUptime,
                        targetDate: effTarget,
                        targetUptime: ProcessInfo.processInfo.systemUptime + TimeInterval(secs),
                        seconds: secs,
                        kind: .step,
                        baseID: nil,
                        isFirstRun: nil,
                        minLeadSeconds: Self.minLeadSecondsNormal,
                        allowSnooze: allowSnooze,
                        soundName: carriedName,
                        snoozeMinutes: snoozeMins,
                        build: nil,
                        source: "chainShift",
                        nominalDate: newNominal,
                        nominalSource: "newBase+offset"
                    )
                )

                let enforcedStr = enforced != nil ? "\(enforced!)s" : "-"
                DiagLog.log("[CHAIN] resched id=\(newID.uuidString) prev=\(oldID.uuidString) offset=\(Int(offset))s newTarget=\(DiagLog.f(newNominal)) enforcedLead=\(enforcedStr) kind=\(kind)")
            } catch {
                DiagLog.log("[CHAIN] FAILED to reschedule prev=\(oldID.uuidString) error=\(error)")
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
        defaults.removeObject(forKey: expectedKey(for: id))
        defaults.removeObject(forKey: "ak.snoozeMinutes.\(id.uuidString)")
        defaults.removeObject(forKey: "ak.stackName.\(id.uuidString)")
        defaults.removeObject(forKey: "ak.stepTitle.\(id.uuidString)")
        defaults.removeObject(forKey: soundKey(for: id))
        defaults.removeObject(forKey: accentHexKey(for: id))
        // mapping keys
        defaults.removeObject(forKey: stackIDKey(for: id))
        defaults.removeObject(forKey: offsetFromFirstKey(for: id))
        defaults.removeObject(forKey: kindKey(for: id))
        defaults.removeObject(forKey: allowSnoozeKey(for: id))
        groupDefaults?.removeObject(forKey: accentHexKey(for: id))
    }

    // Decide which sound to use: always system default (loops indefinitely)
    private func resolveSound(forStepName name: String?) -> AlertConfiguration.AlertSound {
        .default
    }

    // Verifies that the audio file is actually present in the app bundle
    private func resourceExists(named filename: String) -> Bool {
        let ns = filename as NSString
        let name = ns.deletingPathExtension
        let ext  = ns.pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext) != nil
    }

    // MARK: - Test ring (AlarmKit-only)

    @discardableResult
    func scheduleTestRing(in seconds: Int = 5) async -> String? {
        do {
            try await requestAuthorizationIfNeeded()

            let id = UUID()
            let delay = max(1, seconds)
            let target = Date().addingTimeInterval(TimeInterval(delay))

            let title: LocalizedStringResource = LocalizedStringResource("Test Alarm")
            let alert = makeAlert(title: title, allowSnooze: false)
            let tint  = ThemeTintResolver.currentAccent()
            let attrs = makeAttributes(alert: alert, tint: tint)
            let sound = resolveSound(forStepName: nil)

            let stopI = StopAlarmIntent(alarmID: id.uuidString)

            let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                duration: TimeInterval(delay),
                attributes: attrs,
                stopIntent: stopI,
                secondaryIntent: nil,
                sound: sound
            )

            _ = try await manager.schedule(id: id, configuration: cfg)

            defaults.set(target.timeIntervalSince1970, forKey: expectedKey(for: id))
            #if canImport(UIKit)
            if let hx = hex(from: tint) {
                defaults.set(hx, forKey: accentHexKey(for: id))
                groupDefaults?.set(hx, forKey: accentHexKey(for: id))
            }
            #endif

            DiagLog.log("AK test schedule id=\(id.uuidString) in \(delay)s; target=\(DiagLog.f(target))")
            return id.uuidString
        } catch {
            DiagLog.log("AK test schedule FAILED error=\(error)")
            return nil
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
