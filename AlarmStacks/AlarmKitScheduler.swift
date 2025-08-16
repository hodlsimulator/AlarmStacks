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
import UserNotifications
import os.log

@MainActor
final class AppAlarmKitScheduler {
    static let shared = AppAlarmKitScheduler()

    private let manager  = AlarmManager.shared
    private let defaults = UserDefaults.standard
    private let log      = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AlarmKit")

    private init() {}

    private func storageKey(for stack: Stack) -> String { "alarmkit.ids.\(stack.id.uuidString)" }

    // MARK: - Permissions

    func requestAuthorizationIfNeeded() async throws {
        let currentAuth = self.manager.authorizationState
        self.log.info("AK authState=\(String(describing: currentAuth))")
        switch currentAuth {
        case .authorized:
            return
        case .denied:
            throw NSError(
                domain: "AlarmStacks",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Alarm permission denied"]
            )
        case .notDetermined:
            let state = try await self.manager.requestAuthorization()
            self.log.info("AK requestAuthorization -> \(String(describing: state))")
            guard state == .authorized else {
                throw NSError(
                    domain: "AlarmStacks",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "Alarm permission not granted"]
                )
            }
        @unknown default:
            throw NSError(
                domain: "AlarmStacks",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Unknown AlarmKit authorisation state"]
            )
        }
    }

    // MARK: - Scheduling (AlarmKit for truth; optional UN boost for unlocked)
    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        do { try await requestAuthorizationIfNeeded() }
        catch {
            self.log.error("AK auth error -> UN fallback: \(error as NSError)")
            return try await UN_schedule(stack: stack, calendar: calendar)
        }

        await cancelAll(for: stack)
        await UN_cancelAllBoosts() // clean any stray boosts

        var lastFireDate = Date()
        var akIDs: [UUID] = []
        var failureError: NSError?

        for (index, step) in stack.sortedSteps.enumerated() where step.isEnabled {
            // Target fire date
            let fireDate: Date
            switch step.kind {
            case .fixedTime:
                fireDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
                lastFireDate = fireDate
            case .timer, .relativeToPrev:
                fireDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
                lastFireDate = fireDate
            }

            // Build AK alert + attributes
            let title: LocalizedStringResource = LocalizedStringResource("\(stack.name) — \(step.title)")
            let alert = makeAlert(title: title, allowSnooze: step.allowSnooze)
            let attrs  = makeAttributes(alert: alert)

            // Convert to a countdown duration (min 1s) and schedule as TIMER
            let seconds = max(1, Int(ceil(fireDate.timeIntervalSinceNow)))
            let id = UUID()

            do {
                self.log.info("AK scheduling TIMER(id fallback) id=\(id.uuidString) in \(seconds)s for \"\(stack.name) — \(step.title)\"")

                // Your AlarmKit build supports only: .timer(duration:, attributes:)
                let cfg: AlarmManager.AlarmConfiguration<AKVoidMetadata> =
                    .timer(duration: TimeInterval(seconds), attributes: attrs)

                _ = try await self.manager.schedule(id: id, configuration: cfg)

                // Persist per-step snooze minutes for overlay labelling
                AlarmKitSnoozeMap.set(minutes: step.effectiveSnoozeMinutes, for: id)
                akIDs.append(id)

                // Optional “boost”: if unlocked in another app, AK can be subtle (single buzz).
                // We mirror with Time-Sensitive UN banners + sound at +1s (and a couple more pings).
                if Settings.shared.boostUnlockedWithUN {
                    await UN_scheduleMirrorBoostSequence(forAKID: id,
                                                         stack: stack,
                                                         step: step,
                                                         firstFireDate: fireDate.addingTimeInterval(1),
                                                         calendar: calendar)
                }

            } catch {
                failureError = (error as NSError)
                self.log.error("AK schedule error id=\(id.uuidString): \(error as NSError)")
                break
            }
        }

        if let err = failureError {
            for u in akIDs {
                try? self.manager.cancel(id: u)
                AlarmKitSnoozeMap.remove(for: u)
            }
            self.log.warning("AK fallback -> UN notifications for stack \"\(stack.name)\". reason=\(String(describing: err))")
            return try await UN_schedule(stack: stack, calendar: calendar)
        } else {
            let strings = akIDs.map(\.uuidString)
            self.defaults.set(strings, forKey: storageKey(for: stack))
            self.log.info("AK scheduled \(strings.count) item(s) for stack \"\(stack.name)\"")
            return strings
        }
    }

    func cancelAll(for stack: Stack) async {
        let key = storageKey(for: stack)
        let ids = (self.defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
        for id in ids {
            try? self.manager.cancel(id: id)
        }
        AlarmKitSnoozeMap.removeAll(for: ids)
        self.defaults.removeObject(forKey: key)

        await UN_cancelAll(for: stack)
        await UN_cancelAllBoosts()
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        for s in stacks where s.isArmed {
            _ = try? await schedule(stack: s, calendar: calendar)
        }
    }
}

// MARK: - AlarmKit helpers

private struct AKVoidMetadata: AlarmMetadata {}

private func makeAlert(title: LocalizedStringResource, allowSnooze: Bool) -> AlarmPresentation.Alert {
    let stop = AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
    if allowSnooze {
        let snooze = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
        return AlarmPresentation.Alert(
            title: title,
            stopButton: stop,
            secondaryButton: snooze,
            secondaryButtonBehavior: .countdown
        )
    } else {
        return AlarmPresentation.Alert(
            title: title,
            stopButton: stop,
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
    }
}

private func makeAttributes(alert: AlarmPresentation.Alert) -> AlarmAttributes<AKVoidMetadata> {
    AlarmAttributes(
        presentation: AlarmPresentation(alert: alert),
        tintColor: Color(hex: "#0A84FF")
    )
}

// MARK: - UN fallback (full stack) — unchanged, used when AK unavailable

@MainActor
private func UN_schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
    let center = UNUserNotificationCenter.current()
    var settings = await center.notificationSettings()
    if settings.authorizationStatus == .notDetermined {
        let granted = try await center.requestAuthorization(
            options: [.alert, .sound, .badge, .providesAppNotificationSettings]
        )
        if !granted {
            throw NSError(domain: "AlarmStacks",
                          code: 2001,
                          userInfo: [NSLocalizedDescriptionKey: "Notifications permission denied"])
        }
        settings = await center.notificationSettings()
    }

    await UN_cancelAll(for: stack)

    var identifiers: [String] = []
    var lastFireDate: Date = Date()

    let sound = await UN_bestSound()

    for (index, step) in stack.sortedSteps.enumerated() where step.isEnabled {
        let fireDate: Date
        switch step.kind {
        case .fixedTime:
            fireDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
            lastFireDate = fireDate
        case .timer, .relativeToPrev:
            fireDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
            lastFireDate = fireDate
        }

        let id = "stack-\(stack.id.uuidString)-step-\(step.id.uuidString)-\(index)"
        let content = UN_buildContent(for: step, stackName: stack.name, stackID: stack.id.uuidString, sound: sound)

        let trigger: UNNotificationTrigger
        if step.kind == .fixedTime || step.kind == .relativeToPrev {
            let comps = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            let interval = max(1, Int(fireDate.timeIntervalSinceNow.rounded()))
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(interval), repeats: false)
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
        identifiers.append(id)
    }

    return identifiers
}

// MARK: - UN “mirror boost” sequence for unlocked (soundy banners)

@MainActor
private func UN_scheduleMirrorBoostSequence(forAKID akID: UUID,
                                            stack: Stack,
                                            step: Step,
                                            firstFireDate: Date,
                                            calendar: Calendar) async {
    let count = max(1, Settings.shared.unlockedBoostCount)
    let spacing = max(1, Settings.shared.unlockedBoostSpacingSeconds)
    let center = UNUserNotificationCenter.current()
    var settings = await center.notificationSettings()
    if settings.authorizationStatus == .notDetermined {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings])
        settings = await center.notificationSettings()
    }

    let sound = await UN_bestSound()

    for i in 0..<count {
        let when = firstFireDate.addingTimeInterval(TimeInterval(i * spacing))
        let id = "ak-boost-\(akID.uuidString)-\(i)"

        let content = UN_buildContent(for: step,
                                      stackName: stack.name,
                                      stackID: "akboost-\(stack.id.uuidString)",
                                      sound: sound)

        let trigger: UNNotificationTrigger
        if step.kind == .fixedTime || step.kind == .relativeToPrev {
            let comps = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second], from: when)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            let interval = max(1, Int(when.timeIntervalSinceNow.rounded()))
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(interval), repeats: false)
        }

        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(req)
    }

    let mirrorLog = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "UNMirror")
    mirrorLog.info("UN mirror scheduled \(count) boost ping(s) for AK id \(akID.uuidString)")
}

@MainActor
private func UN_bestSound() async -> UNNotificationSound {
    let s = await UNUserNotificationCenter.current().notificationSettings()
    if #available(iOS 15.0, *), s.criticalAlertSetting == .enabled {
        return UNNotificationSound.defaultCriticalSound(withAudioVolume: 1.0)
    }
    if Bundle.main.url(forResource: "AlarmLoud", withExtension: "caf") != nil {
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: "AlarmLoud.caf"))
    }
    return UNNotificationSound.default
}

// MARK: - UN helpers

@MainActor
private func UN_cancelAll(for stack: Stack) async {
    let center = UNUserNotificationCenter.current()
    let prefix = "stack-\(stack.id.uuidString)-"

    let pending = await UN_pendingIDs(prefix: prefix)
    center.removePendingNotificationRequests(withIdentifiers: pending)

    let delivered = await UN_deliveredIDs(prefix: prefix)
    center.removeDeliveredNotifications(withIdentifiers: delivered)
}

@MainActor
private func UN_cancelAllBoosts() async {
    let center = UNUserNotificationCenter.current()
    let pending = await UN_pendingIDs(prefix: "ak-boost-")
    center.removePendingNotificationRequests(withIdentifiers: pending)
    let delivered = await UN_deliveredIDs(prefix: "ak-boost-")
    center.removeDeliveredNotifications(withIdentifiers: delivered)
}

@MainActor
private func UN_pendingIDs(prefix: String) async -> [String] {
    let center = UNUserNotificationCenter.current()
    let requests = await center.pendingNotificationRequests()
    return requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
}

@MainActor
private func UN_deliveredIDs(prefix: String) async -> [String] {
    let center = UNUserNotificationCenter.current()
    let delivered = await center.deliveredNotifications()
    return delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
}

private func UN_buildContent(for step: Step,
                             stackName: String,
                             stackID: String,
                             sound: UNNotificationSound) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = stackName
    content.subtitle = step.title
    content.body = UN_body(for: step)
    content.sound = sound
    content.interruptionLevel = .timeSensitive
    content.threadIdentifier = "stack-\(stackID)"
    content.categoryIdentifier = "ALARM_CATEGORY"
    content.userInfo = [
        "stackID": stackID,
        "stepID": step.id.uuidString,
        "snoozeMinutes": step.effectiveSnoozeMinutes,
        "allowSnooze": step.allowSnooze
    ]
    return content
}

private func UN_body(for step: Step) -> String {
    switch step.kind {
    case .fixedTime:
        if let h = step.hour, let m = step.minute {
            return String(format: "Scheduled for %02d:%02d", h, m)
        }
        return "Scheduled"
    case .timer:
        if let s = step.durationSeconds { return "Timer \(UN_format(seconds: s))" }
        return "Timer"
    case .relativeToPrev:
        if let s = step.offsetSeconds { return "Starts \(UN_formatOffset(seconds: s)) after previous" }
        return "Next step"
    }
}

private func UN_format(seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m \(s)s" }
    return "\(s)s"
}

private func UN_formatOffset(seconds: Int) -> String {
    seconds >= 0 ? "+\(UN_format(seconds: seconds))" : "−\(UN_format(seconds: -seconds))"
}

#endif
