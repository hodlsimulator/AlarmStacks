//
//  AlarmKitScheduler+Snooze.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//

#if canImport(AlarmKit)

import Foundation
import SwiftUI
import AlarmKit
import ActivityKit
import AppIntents

@MainActor
extension AlarmKitScheduler {

    // MARK: Keys used here (reuse helpers defined in base class)
    private func nominalKey(for id: UUID) -> String { expectedKey(for: id) } // steps’ nominal (calendar)
    private func snoozeMinutesKey(for id: UUID) -> String { "ak.snoozeMinutes.\(id.uuidString)" }
    private func stackNameKey(for id: UUID) -> String { "ak.stackName.\(id.uuidString)" }
    private func stepTitleKey(for id: UUID) -> String { "ak.stepTitle.\(id.uuidString)" }

    // MARK: Public entrypoint used by AppIntent
    /// Unified path for snoozing from an alert (baseID may be a step id or a prior snooze id).
    @discardableResult
    func snoozeFromIntent(baseAlarmID: UUID) async -> String? {
        // Silence current ring immediately
        try? manager.stop(id: baseAlarmID)

        // Gate by per-id allowSnooze (default FALSE)
        let allow = (defaults.object(forKey: allowSnoozeKey(for: baseAlarmID)) as? Bool) ?? false
        if allow == false {
            DiagLog.log("SNOOZE IGNORED (disabled) id=\(baseAlarmID.uuidString)")
            return nil
        }

        // Read minutes, stack/step names from the base alarm id
        let minutes = max(1, defaults.integer(forKey: snoozeMinutesKey(for: baseAlarmID)))
        let stackName = defaults.string(forKey: stackNameKey(for: baseAlarmID)) ?? "Alarm"
        let stepTitle = defaults.string(forKey: stepTitleKey(for: baseAlarmID)) ?? "Snoozed"

        return await scheduleSnoozeAndShiftChain(baseAlarmID: baseAlarmID,
                                                 stackName: stackName,
                                                 stepTitle: stepTitle,
                                                 minutes: minutes)
    }

    // MARK: Core: schedule the snooze alarm and shift chain deterministically
    @discardableResult
    private func scheduleSnoozeAndShiftChain(
        baseAlarmID: UUID,
        stackName: String,
        stepTitle: String,
        minutes: Int
    ) async -> String? {

        // Cancel an existing active snooze tied to this base (if any)
        if let existing = defaults.string(forKey: snoozeMapKey(for: baseAlarmID)),
           let existingID = UUID(uuidString: existing) {
            try? manager.cancel(id: existingID)
            cleanupMetadata(for: existingID)
            defaults.removeObject(forKey: snoozeMapKey(for: baseAlarmID))
        }

        // Resolve stack + base offset
        guard let stackID = defaults.string(forKey: stackIDKey(for: baseAlarmID)) else {
            DiagLog.log("[CHAIN] snooze? base=\(baseAlarmID.uuidString) (no stackID)")
            return nil
        }
        let firstEpoch = defaults.double(forKey: firstTargetKey(forStackID: stackID))
        guard firstEpoch > 0 else {
            DiagLog.log("[CHAIN] snooze? stack=\(stackID) (no first target)")
            return nil
        }
        let firstDate  = Date(timeIntervalSince1970: firstEpoch)
        let baseOffset = (defaults.object(forKey: offsetFromFirstKey(for: baseAlarmID)) as? Double) ?? 0
        let isFirst    = abs(baseOffset) < 0.5

        // Compute Δ strictly from nominal: oldNominal(base) = first + offset
        let oldNominal = firstDate.addingTimeInterval(baseOffset)

        // New snooze fire time (effective), ≥ 60 s from now
        let snoozeSecs = max(Self.minLeadSecondsNormal, minutes * 60)
        let newBase    = Date().addingTimeInterval(TimeInterval(snoozeSecs))
        let delta      = newBase.timeIntervalSince(oldNominal)

        // Build snooze alert (always allows re-snooze)
        let stop  = AlarmButton(text: LocalizedStringResource("Stop"),  textColor: .white, systemImageName: "stop.fill")
        let again = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")

        // Carry the exact accent/sound of the base alarm
        let carriedHex  = defaults.string(forKey: accentHexKey(for: baseAlarmID)) ?? groupDefaults?.string(forKey: accentHexKey(for: baseAlarmID))
        let tint: SwiftUI.Color = {
            if let hx = carriedHex, !hx.isEmpty { return colorFromHex(hx) }
            return ThemeTintResolver.currentAccent()
        }()
        let carriedSound = defaults.string(forKey: soundKey(for: baseAlarmID))
        let attrs = AlarmAttributes<EmptyMetadata>(
            presentation: AlarmPresentation(alert:
                AlarmPresentation.Alert(title: LocalizedStringResource("\(stackName) — \(stepTitle)"),
                                        stopButton: stop,
                                        secondaryButton: again,
                                        secondaryButtonBehavior: .countdown)),
            tintColor: tint
        )

        // Schedule the snooze timer itself
        let snoozeID = UUID()
        do {
            let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                duration: TimeInterval(snoozeSecs),
                attributes: attrs,
                stopIntent: StopAlarmIntent(alarmID: snoozeID.uuidString),
                secondaryIntent: SnoozeAlarmIntent(alarmID: snoozeID.uuidString),
                sound: .default
            )
            _ = try await manager.schedule(id: snoozeID, configuration: cfg)
        } catch {
            DiagLog.log("AK snooze schedule FAILED base=\(baseAlarmID.uuidString) error=\(error)")
            return nil
        }

        // Persist snooze metadata (EFFECTIVE target only)
        defaults.set(newBase.timeIntervalSince1970, forKey: effTargetKey(for: snoozeID))
        defaults.set(snoozeID.uuidString, forKey: snoozeMapKey(for: baseAlarmID))
        defaults.set(minutes, forKey: snoozeMinutesKey(for: snoozeID))
        defaults.set(stackName, forKey: stackNameKey(for: snoozeID))
        defaults.set(stepTitle, forKey: stepTitleKey(for: snoozeID))
        if let n = carriedSound, !n.isEmpty { defaults.set(n, forKey: soundKey(for: snoozeID)) }
        if let hx = carriedHex { defaults.set(hx, forKey: accentHexKey(for: snoozeID)) }
        defaults.set(true, forKey: allowSnoozeKey(for: snoozeID)) // snooze alert always re-snoozable

        // IMPORTANT: give the snooze its correct chain mapping.
        // If the base was the FIRST step, the snooze becomes the new base => offset 0.
        // Otherwise (middle snooze), offsetFromFirst(base) += Δ.
        if isFirst {
            defaults.set(stackID, forKey: stackIDKey(for: snoozeID))
            defaults.set(0.0,     forKey: offsetFromFirstKey(for: snoozeID))   // ✅ fix: offset must be 0 for first-step snooze
            defaults.set("timer", forKey: kindKey(for: snoozeID))
        } else {
            let newOffset = baseOffset + delta
            defaults.set(stackID,   forKey: stackIDKey(for: snoozeID))
            defaults.set(newOffset, forKey: offsetFromFirstKey(for: snoozeID))
            defaults.set("timer",   forKey: kindKey(for: snoozeID))
        }

        DiagLog.log("AK snooze schedule base=\(baseAlarmID.uuidString) id=\(snoozeID.uuidString) secs=\(snoozeSecs) effTarget=\(DiagLog.f(newBase)) Δ=\(String(format: "%.3fs", delta)) baseOffset=\(String(format: "%.1fs", baseOffset)) isFirst=\(isFirst ? "y":"n")")

        // Chain shift — and update the tracked ids to include the snooze in place of base
        await shiftChainAfterSnooze(baseAlarmID: baseAlarmID, newBase: newBase, snoozeID: snoozeID, baseIsFirst: isFirst, delta: delta, firstDate: firstDate, baseOffset: baseOffset, stackID: stackID, snoozeSecs: snoozeSecs)

        return snoozeID.uuidString
    }

    // MARK: - Chain shift (first or middle)
    private func shiftChainAfterSnooze(
        baseAlarmID: UUID,
        newBase: Date,
        snoozeID: UUID,
        baseIsFirst: Bool,
        delta: TimeInterval,
        firstDate: Date,
        baseOffset: TimeInterval,
        stackID: String,
        snoozeSecs: Int
    ) async {
        var tracked = defaults.stringArray(forKey: storageKey(forStackID: stackID)) ?? []

        if tracked.isEmpty {
            DiagLog.log("[CHAIN] no tracked IDs for stack=\(stackID); abort shift")
            return
        }

        // Replace base id -> snooze id in the tracked list
        if let idx = tracked.firstIndex(of: baseAlarmID.uuidString) {
            tracked[idx] = snoozeID.uuidString
            defaults.set(tracked, forKey: storageKey(forStackID: stackID))
        } else {
            tracked.append(snoozeID.uuidString)
            defaults.set(tracked, forKey: storageKey(forStackID: stackID))
        }

        // Update anchor
        if baseIsFirst {
            defaults.set(newBase.timeIntervalSince1970, forKey: firstTargetKey(forStackID: stackID))
        } else {
            defaults.set(baseOffset + delta, forKey: offsetFromFirstKey(for: baseAlarmID))
        }

        DiagLog.log(String(format: "[CHAIN] shift stack=%@ base=%@ → snooze=%@ newBase=%@ Δ=%+.3fs baseOffset=%.1fs isFirst=%@",
                           stackID, baseAlarmID.uuidString, snoozeID.uuidString, DiagLog.f(newBase), delta, baseOffset, baseIsFirst ? "y":"n"))

        // Reschedule impacted steps — DO NOT gate on 'expected/nominal' presence.
        for oldStr in tracked {
            guard let oldID = UUID(uuidString: oldStr) else { continue }
            if oldID == baseAlarmID || oldID == snoozeID { continue }

            let kind = defaults.string(forKey: kindKey(for: oldID)) ?? "timer"
            if kind == "fixed" {
                DiagLog.log("[CHAIN] skip fixed id=\(oldID.uuidString)")
                continue
            }

            guard let off = defaults.object(forKey: offsetFromFirstKey(for: oldID)) as? Double else {
                DiagLog.log("[CHAIN] skip id=\(oldID.uuidString) (no offset)")
                continue
            }
            if baseIsFirst == false && off <= baseOffset { continue }

            // Carry metadata BEFORE cleanup (fallbacks if missing)
            let stackName  = defaults.string(forKey: "ak.stackName.\(oldID.uuidString)") ?? "Alarm"
            let stepTitle  = defaults.string(forKey: "ak.stepTitle.\(oldID.uuidString)") ?? "Step"
            let allow      = (defaults.object(forKey: allowSnoozeKey(for: oldID)) as? Bool) ?? false
            let snoozeMins = defaults.integer(forKey: "ak.snoozeMinutes.\(oldID.uuidString)")
            let carried    = defaults.string(forKey: soundKey(for: oldID))
            let hx = defaults.string(forKey: accentHexKey(for: oldID))
                ?? defaults.string(forKey: "themeAccentHex") ?? "#3A7BFF"
            let tint = colorFromHex(hx)

            // New nominal & offset
            let newOffset  = baseIsFirst ? off : (off + delta)
            let newNominal = baseIsFirst ? newBase.addingTimeInterval(off)
                                         : firstDate.addingTimeInterval(newOffset)

            // Enforce ≥60 s lead; guarantee snooze comes first in first-step case
            let now = Date()
            let raw = max(0, newNominal.timeIntervalSince(now))
            var secs = max(Self.minLeadSecondsNormal, Int(ceil(raw)))
            if baseIsFirst, secs <= snoozeSecs { secs = snoozeSecs + 1 }
            let enforcedStr = secs > Int(ceil(raw)) ? "\(secs)s" : "-"

            // Cancel previous + cleanup
            try? manager.cancel(id: oldID)
            cleanupMetadata(for: oldID)

            // Schedule replacement
            let newID = UUID()
            let title: LocalizedStringResource = LocalizedStringResource("\(stackName) — \(stepTitle)")
            let stop = AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
            let alert: AlarmPresentation.Alert = {
                if allow {
                    let snooze = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
                    return AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: snooze, secondaryButtonBehavior: .countdown)
                } else {
                    return AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: nil, secondaryButtonBehavior: nil)
                }
            }()
            let attrs = AlarmAttributes<EmptyMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: tint)
            let stopI   = StopAlarmIntent(alarmID: newID.uuidString)
            let snoozeI = allow ? SnoozeAlarmIntent(alarmID: newID.uuidString) : nil

            do {
                let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                    duration: TimeInterval(secs),
                    attributes: attrs,
                    stopIntent: stopI,
                    secondaryIntent: snoozeI,
                    sound: .default
                )
                _ = try await manager.schedule(id: newID, configuration: cfg)

                // Persist new id metadata (nominal for steps)
                defaults.set(newNominal.timeIntervalSince1970, forKey: expectedKey(for: newID))
                defaults.set(stackName,  forKey: "ak.stackName.\(newID.uuidString)")
                defaults.set(stepTitle,  forKey: "ak.stepTitle.\(newID.uuidString)")
                defaults.set(allow,      forKey: allowSnoozeKey(for: newID))
                defaults.set(snoozeMins, forKey: "ak.snoozeMinutes.\(newID.uuidString)")
                if let n = carried, !n.isEmpty { defaults.set(n, forKey: soundKey(for: newID)) }
                defaults.set(hx,         forKey: accentHexKey(for: newID))

                // Preserve mapping
                defaults.set(stackID,   forKey: stackIDKey(for: newID))
                defaults.set(newOffset, forKey: offsetFromFirstKey(for: newID))
                defaults.set(kind,      forKey: kindKey(for: newID))

                // Swap id in tracked list
                if let idx = tracked.firstIndex(of: oldStr) { tracked[idx] = newID.uuidString }
                defaults.set(tracked, forKey: storageKey(forStackID: stackID))

                DiagLog.log("[CHAIN] resched id=\(newID.uuidString) prev=\(oldID.uuidString) newOffset=\(String(format: "%.1fs", newOffset)) newTarget=\(DiagLog.f(newNominal)) enforcedLead=\(enforcedStr) kind=\(kind) allowSnooze=\(allow)")
            } catch {
                DiagLog.log("[CHAIN] FAILED to reschedule prev=\(oldID.uuidString) error=\(error)")
            }
        }
    }

    // MARK: Cleanup (same keys as base)
    private func cleanupMetadata(for id: UUID) {
        defaults.removeObject(forKey: expectedKey(for: id))          // nominal
        defaults.removeObject(forKey: effTargetKey(for: id))         // effective
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
    
    // MARK: - Public wrappers for legacy callers

    /// Legacy entrypoint used by AlarmController etc.
    /// Schedules a snooze for `baseAlarmID` with the provided metadata,
    /// then applies the chain shift. Delegates to the new central path.
    @discardableResult
    func scheduleSnooze(
        baseAlarmID: UUID,
        stackName: String,
        stepTitle: String,
        minutes: Int
    ) async -> String? {
        return await scheduleSnoozeAndShiftChain(
            baseAlarmID: baseAlarmID,
            stackName: stackName,
            stepTitle: stepTitle,
            minutes: minutes
        )
    }

    /// Convenience overload that reads the metadata from UserDefaults
    /// (matches what older code paths expected).
    @discardableResult
    func scheduleSnooze(baseAlarmID: UUID) async -> String? {
        let ud = UserDefaults.standard
        let minutes   = max(1, ud.integer(forKey: "ak.snoozeMinutes.\(baseAlarmID.uuidString)"))
        let stackName = ud.string(forKey: "ak.stackName.\(baseAlarmID.uuidString)") ?? "Alarm"
        let stepTitle = ud.string(forKey: "ak.stepTitle.\(baseAlarmID.uuidString)") ?? "Snoozed"
        return await scheduleSnoozeAndShiftChain(
            baseAlarmID: baseAlarmID,
            stackName: stackName,
            stepTitle: stepTitle,
            minutes: minutes
        )
    }
}

extension AlarmKitScheduler: AlarmSnoozing {}

#endif
