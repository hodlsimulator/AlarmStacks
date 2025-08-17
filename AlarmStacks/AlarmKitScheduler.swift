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
import os.log

@MainActor
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    private let manager  = AlarmManager.shared
    private let defaults = UserDefaults.standard
    private let fallback = UserNotificationScheduler.shared
    private let log      = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AlarmKit")

    private init() {}

    private func storageKey(for stack: Stack) -> String { "alarmkit.ids.\(stack.id.uuidString)" }

    // MARK: - Permissions

    func requestAuthorizationIfNeeded() async throws {
        let currentAuth = self.manager.authorizationState
        self.log.info("AK authState=\(String(describing: currentAuth), privacy: .public)")
        switch currentAuth {
        case .authorized: return
        case .denied:
            throw NSError(domain: "AlarmStacks", code: 1001,
                          userInfo: [NSLocalizedDescriptionKey: "Alarm permission denied"])
        case .notDetermined:
            let state = try await self.manager.requestAuthorization()
            self.log.info("AK requestAuthorization -> \(String(describing: state), privacy: .public)")
            guard state == .authorized else {
                throw NSError(domain: "AlarmStacks", code: 1002,
                              userInfo: [NSLocalizedDescriptionKey: "Alarm permission not granted"])
            }
        @unknown default:
            throw NSError(domain: "AlarmStacks", code: 1003,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown AlarmKit authorisation state"])
        }
    }

    // MARK: - Scheduling (timers only; fixed-time converted to countdown)
    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        // If AK auth fails (or framework unavailable), use notifications.
        do { try await requestAuthorizationIfNeeded() }
        catch {
            self.log.error("AK auth error -> using UN fallback: \(error as NSError, privacy: .public)")
            let ids = try await self.fallback.schedule(stack: stack, calendar: calendar)
            await LiveActivityManager.start(for: stack, calendar: calendar)
            return ids
        }

        await cancelAll(for: stack) // clear persisted AK IDs and any UN notifs

        var lastFireDate = Date()
        var akIDs: [UUID] = []
        var akFailed = false
        var failureError: NSError?

        for step in stack.sortedSteps where step.isEnabled {
            // Compute target wall-clock time for this step
            let fireDate: Date
            switch step.kind {
            case .fixedTime:
                fireDate = try step.nextFireDate(basedOn: Date(), calendar: calendar)
                lastFireDate = fireDate
            case .timer, .relativeToPrev:
                fireDate = try step.nextFireDate(basedOn: lastFireDate, calendar: calendar)
                lastFireDate = fireDate
            }

            // Build alert + attributes (snooze via .countdown behaviour)
            let title: LocalizedStringResource = LocalizedStringResource("\(stack.name) — \(step.title)")
            let alert = makeAlert(title: title, allowSnooze: step.allowSnooze)
            let attrs  = makeAttributes(alert: alert)

            // Schedule as TIMER (AlarmKit .alarm(at:) not available in your SDK)
            let id = UUID()
            do {
                let seconds = max(1, Int(ceil(fireDate.timeIntervalSinceNow)))
                let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> =
                    .timer(duration: TimeInterval(seconds), attributes: attrs)
                _ = try await self.manager.schedule(id: id, configuration: cfg)
                akIDs.append(id)
            } catch {
                akFailed = true
                failureError = (error as NSError)
                self.log.error("AK schedule error id=\(id.uuidString, privacy: .public): \(error as NSError, privacy: .public)")
                break
            }
        }

        if akFailed {
            // Roll back anything we placed with AK, then fall back to notifications.
            for u in akIDs { try? self.manager.cancel(id: u) }
            self.log.warning("AK fallback -> UN notifications for stack \"\(stack.name, privacy: .public)\". reason=\(String(describing: failureError), privacy: .public)")
            let ids = try await self.fallback.schedule(stack: stack, calendar: calendar)
            await LiveActivityManager.start(for: stack, calendar: calendar)
            return ids
        } else {
            let strings = akIDs.map(\.uuidString)
            self.defaults.set(strings, forKey: storageKey(for: stack))
            self.log.info("AK scheduled \(strings.count, privacy: .public) timer(s) for stack \"\(stack.name, privacy: .public)\"")
            await LiveActivityManager.start(for: stack, calendar: calendar)
            return strings
        }
    }


    func cancelAll(for stack: Stack) async {
        // Cancel AK timers we persisted.
        let key = storageKey(for: stack)
        for s in (self.defaults.stringArray(forKey: key) ?? []) {
            if let id = UUID(uuidString: s) { try? self.manager.cancel(id: id) }
        }
        self.defaults.removeObject(forKey: key)

        // Also cancel any notifications created by fallback.
        await self.fallback.cancelAll(for: stack)
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        for s in stacks where s.isArmed {
            _ = try? await schedule(stack: s, calendar: calendar)
        }
    }
}

// MARK: - AlarmKit helpers

nonisolated struct EmptyMetadata: AlarmMetadata {}

private func makeAlert(title: LocalizedStringResource, allowSnooze: Bool) -> AlarmPresentation.Alert {
    let stop = AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
    if allowSnooze {
        let snooze = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
        // Explicit snooze behaviour so AK doesn't expect a custom App Intent.
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

private func makeAttributes(alert: AlarmPresentation.Alert) -> AlarmAttributes<EmptyMetadata> {
    // Blue accent for better contrast/legibility
    AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                    tintColor: Color(red: 0.04, green: 0.52, blue: 1.00)) // #0A84FF
}

#endif
