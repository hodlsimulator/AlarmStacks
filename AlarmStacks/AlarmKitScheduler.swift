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
import AppIntents   
import ActivityKit
import os.log

@MainActor
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    private let manager  = AlarmManager.shared
    private let defaults = UserDefaults.standard
    private let log      = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AlarmKit")

    // MARK: Tunables
    // Longer runway so the system presents the full AK overlay (avoids “single buzz”).
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

    private func storageKey(for stack: Stack) -> String { "alarmkit.ids.\(stack.id.uuidString)" }
    private func expectedKey(for id: UUID) -> String { "ak.expected.\(id.uuidString)" }
    private func snoozeMapKey(for base: UUID) -> String { "ak.snooze.map.\(base.uuidString)" }
    private func soundKey(for id: UUID) -> String { "ak.soundName.\(id.uuidString)" }

    // MARK: - Permissions

    func requestAuthorizationIfNeeded() async throws {
        switch manager.authorizationState {
        case .authorized:
            return
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

    // MARK: - Scheduling (single AK timer per step)

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

        for step in stack.sortedSteps where step.isEnabled {
            let nominalDate: Date
            switch step.kind {
            case .fixedTime:
                nominalDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
                lastFireDate = nominalDate
            case .timer, .relativeToPrev:
                nominalDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
                lastFireDate = nominalDate
            }

            let now = Date()
            let raw = max(0, nominalDate.timeIntervalSince(now))
            let seconds = max(minLead, Int(ceil(raw)))
            let effectiveTarget = now.addingTimeInterval(TimeInterval(seconds))

            let title: LocalizedStringResource = LocalizedStringResource("\(stack.name) — \(step.title)")
            let alert = makeAlert(title: title, allowSnooze: step.allowSnooze)
            let attrs  = makeAttributes(alert: alert)
            let sound  = resolveSound(forStepName: step.soundName)

            let id = UUID()
            log.info("AK schedule id=\(id.uuidString, privacy: .public) timer in \(seconds, privacy: .public)s; stack=\(stack.name, privacy: .public); step=\(step.title, privacy: .public); effTarget=\(effectiveTarget as NSDate, privacy: .public) nominal=\(nominalDate as NSDate, privacy: .public)")
            DiagLog.log("AK schedule id=\(id.uuidString) timer in \(seconds)s; stack=\(stack.name); step=\(step.title); effTarget=\(DiagLog.f(effectiveTarget)) nominal=\(DiagLog.f(nominalDate)) shift=\(String(format: "%.3fs", effectiveTarget.timeIntervalSince(nominalDate)))")

            defaults.set(effectiveTarget.timeIntervalSince1970, forKey: expectedKey(for: id))
            if let n = step.soundName, !n.isEmpty { defaults.set(n, forKey: soundKey(for: id)) }
            else if let n = Self.defaultSoundFilename { defaults.set(n, forKey: soundKey(for: id)) }
            defaults.set(step.snoozeMinutes, forKey: "ak.snoozeMinutes.\(id.uuidString)")
            defaults.set(stack.name,        forKey: "ak.stackName.\(id.uuidString)")
            defaults.set(step.title,        forKey: "ak.stepTitle.\(id.uuidString)")

            // Hook system buttons to our code via AppIntents (no availability checks needed on iOS 26+)
            let stopI   = StopAlarmIntent(alarmID: id.uuidString)
            let snoozeI = SnoozeAlarmIntent(alarmID: id.uuidString)

            let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                duration: TimeInterval(seconds),
                attributes: attrs,
                stopIntent: stopI,
                secondaryIntent: snoozeI,
                sound: sound
            )
            _ = try await manager.schedule(id: id, configuration: cfg)

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
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                    source: "AlarmKitScheduler.schedule",
                    nominalDate: nominalDate,
                    nominalSource: "Step.nextFireDate"
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

    // MARK: - AlarmKit Snooze (timer-based; AK-only)

    /// Schedules a precise AlarmKit snooze for `minutes` from the *Snooze tap* moment (if captured),
    /// falling back to "now" if no tap timestamp exists. Logs set vs actual.
    @discardableResult
    func scheduleSnooze(
        baseAlarmID: UUID,
        stackName: String,
        stepTitle: String,
        minutes: Int
    ) async -> String? {
        if let existing = defaults.string(forKey: snoozeMapKey(for: baseAlarmID)),
           let existingID = UUID(uuidString: existing) {
            try? manager.cancel(id: existingID)
            cleanupExpectationAndMetadata(for: existingID)
            defaults.removeObject(forKey: snoozeMapKey(for: baseAlarmID))
        }

        let id = UUID()
        let setSeconds = max(1, minutes) * 60

        let now   = Date()
        let upNow = ProcessInfo.processInfo.systemUptime

        let (tapWall, _) = AKDiag.loadSnoozeTap(for: baseAlarmID) ?? (now, upNow)
        let desiredTarget = tapWall.addingTimeInterval(TimeInterval(setSeconds))
        var duration = desiredTarget.timeIntervalSince(now)
        if duration < 1 { duration = 1 } // safety floor

        let effTarget = now.addingTimeInterval(duration)

        let title: LocalizedStringResource = LocalizedStringResource("\(stackName) — \(stepTitle)")
        let alert = makeAlert(title: title, allowSnooze: true)
        let attrs = makeAttributes(alert: alert)
        let carriedName = defaults.string(forKey: soundKey(for: baseAlarmID))
        let sound = resolveSound(forStepName: carriedName)

        do {
            // Wire Lock Screen buttons to our intents
            let stopI   = StopAlarmIntent(alarmID: id.uuidString)
            let snoozeI = SnoozeAlarmIntent(alarmID: id.uuidString)

            let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                duration: duration,                    // Double to avoid rounding error
                attributes: attrs,
                stopIntent: stopI,
                secondaryIntent: snoozeI,
                sound: sound
            )
            _ = try await manager.schedule(id: id, configuration: cfg)

            defaults.set(effTarget.timeIntervalSince1970, forKey: expectedKey(for: id))
            defaults.set(id.uuidString, forKey: snoozeMapKey(for: baseAlarmID))
            defaults.set(minutes, forKey: "ak.snoozeMinutes.\(id.uuidString)")
            defaults.set(stackName, forKey: "ak.stackName.\(id.uuidString)")
            defaults.set(stepTitle, forKey: "ak.stepTitle.\(id.uuidString)")
            if let n = carriedName, !n.isEmpty { defaults.set(n, forKey: soundKey(for: id)) }

            let rec = AKDiag.Record(
                stackName: stackName,
                stepTitle: stepTitle,
                scheduledAt: now,
                scheduledUptime: upNow,
                targetDate: effTarget,                          // effective
                targetUptime: upNow + duration,
                seconds: setSeconds,                            // what was set
                kind: .snooze,
                baseID: baseAlarmID.uuidString,
                isFirstRun: false,
                minLeadSeconds: nil,
                allowSnooze: true,
                soundName: carriedName,
                snoozeMinutes: minutes,
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                source: "AlarmKitScheduler.scheduleSnooze(tapAnchored)",
                nominalDate: desiredTarget,                     // desired (tap + N×60)
                nominalSource: "Snooze(tap + N×60s)"
            )
            AKDiag.save(id: id, record: rec)

            AKDiag.markSnoozeChain(
                base: baseAlarmID,
                snooze: id,
                minutes: minutes,
                seconds: Int(duration.rounded()),
                target: effTarget
            )

            DiagLog.log(
                "AK snooze schedule base=\(baseAlarmID.uuidString) id=\(id.uuidString) " +
                "set=\(setSeconds)s dur=\(String(format: "%.3f", duration))s desired=\(DiagLog.f(desiredTarget)) effTarget=\(DiagLog.f(effTarget))"
            )

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
            let attrs = makeAttributes(alert: alert)                   // themed
            let sound = resolveSound(forStepName: nil)

            let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                duration: TimeInterval(delay),
                attributes: attrs,
                stopIntent: nil,
                secondaryIntent: nil,
                sound: sound
            )

            _ = try await manager.schedule(id: id, configuration: cfg)

            // Diagnostics for delta logging
            defaults.set(target.timeIntervalSince1970, forKey: expectedKey(for: id))
            if let def = Self.defaultSoundFilename { defaults.set(def, forKey: soundKey(for: id)) }

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

private func makeAttributes(alert: AlarmPresentation.Alert) -> AlarmAttributes<EmptyMetadata> {
    let presentation = AlarmPresentation(alert: alert)
    return AlarmAttributes<EmptyMetadata>(
        presentation: presentation,
        // Use the current app accent so the AlarmKit banner / Island matches your theme
        tintColor: ThemeTintResolver.currentAccent()
    )
}

#endif
