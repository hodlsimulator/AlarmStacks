//
//  LiveActivityManager.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
import ActivityKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum LiveActivityManager {
    private static var current: Activity<AlarmActivityAttributes>?

    // MARK: - Helpers

    private static func deviceIsEligibleForLA() -> Bool {
        #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom != .phone {
            DiagLog.log("[LA] Not an iPhone; Live Activities don’t render on this device.")
            return false
        }
        #if targetEnvironment(simulator)
        DiagLog.log("[LA] Simulator detected; Live Activities aren’t rendered on Simulator.")
        return false
        #endif
        #endif

        let info = ActivityAuthorizationInfo()
        guard info.areActivitiesEnabled else {
            DiagLog.log("[LA] areActivitiesEnabled == false (global switch off).")
            return false
        }
        return true
    }

    /// Resolve the next enabled step title + fire date for a stack.
    private static func nextStepInfo(for stack: Stack, calendar: Calendar) -> (title: String, fire: Date)? {
        var base = Date()
        for (idx, step) in stack.sortedSteps.enumerated() where step.isEnabled {
            let fire: Date?
            switch step.kind {
            case .fixedTime:
                fire = try? step.nextFireDate(basedOn: Date(), calendar: calendar)
                if let f = fire { base = f }
            case .timer, .relativeToPrev:
                fire = try? step.nextFireDate(basedOn: base, calendar: calendar)
                if let f = fire { base = f }
            }
            if idx == 0, let f = fire {
                return (step.title, f)
            }
        }
        return nil
    }

    private static func currentAccentHex() -> String {
        let std = UserDefaults.standard.string(forKey: "themeAccentHex")
        let grp = UserDefaults(suiteName: AppGroups.main)?.string(forKey: "themeAccentHex")
        let hex = std ?? grp ?? "#3A7BFF"
        // keep intents path fresh
        UserDefaults(suiteName: AppGroups.main)?.set(hex, forKey: "themeAccentHex")
        return hex
    }

    // MARK: - Public API

    static func start(for stack: Stack, calendar: Calendar = .current) async {
        guard deviceIsEligibleForLA() else { return }
        guard let info = nextStepInfo(for: stack, calendar: calendar) else {
            await end()
            return
        }

        let accent = currentAccentHex()
        DiagLog.log("[LA] startResolved stack=\(stack.name) title=\(info.title) fire=\(info.fire)")

        let state = AlarmActivityAttributes.ContentState(
            stackName: stack.name,
            stepTitle: info.title,
            ends: info.fire,
            allowSnooze: true,
            alarmID: "",               // filled on ring
            firedAt: nil,              // pre-ring
            accentHex: accent
        )
        let content = ActivityContent<AlarmActivityAttributes.ContentState>(state: state, staleDate: nil)

        if let activity = current {
            await activity.update(content)
            DiagLog.log("[LA] update success id=\(activity.id)")
            return
        }

        do {
            current = try Activity.request(
                attributes: AlarmActivityAttributes(),
                content: content,
                pushType: nil
            )
            if let id = current?.id { DiagLog.log("[LA] request success id=\(id)") }
        } catch {
            DiagLog.log("[LA] request error \(error)")
        }
    }

    /// Mark that the current step started ringing now.
    static func markFiredNow() async {
        guard let activity = current else { return }
        var st = activity.content.state
        if st.firedAt == nil { st.firedAt = Date() }
        let content = ActivityContent<AlarmActivityAttributes.ContentState>(state: st, staleDate: nil)
        await activity.update(content)
        DiagLog.log("[LA] markFiredNow id=\(activity.id)")
    }

    /// End if time already passed.
    static func endIfExpired() async {
        guard let activity = current else { return }
        let st = activity.content.state
        if st.ends <= Date() {
            let content = ActivityContent<AlarmActivityAttributes.ContentState>(state: st, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            current = nil
            DiagLog.log("[LA] endIfExpired (expired)")
        }
    }

    static func end() async {
        if let activity = current {
            let st = activity.content.state
            let content = ActivityContent<AlarmActivityAttributes.ContentState>(state: st, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            DiagLog.log("[LA] end id=\(activity.id)")
        }
        current = nil
    }
}
