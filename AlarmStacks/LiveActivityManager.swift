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

    // MARK: - Very small eligibility check
    private static func isEligible() -> Bool {
        #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom != .phone {
            DiagLog.log("[LA] not iPhone → skip")
            return false
        }
        #if targetEnvironment(simulator)
        DiagLog.log("[LA] simulator → skip")
        return false
        #endif
        #endif

        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        if !enabled { DiagLog.log("[LA] areActivitiesEnabled == false"); }
        return enabled
    }

    // MARK: - Next step resolution (unchanged logic)
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
        guard isEligible() else { return }
        guard let info = nextStepInfo(for: stack, calendar: calendar) else {
            await end(); return
        }

        let state = AlarmActivityAttributes.ContentState(
            stackName: stack.name,
            stepTitle: info.title,
            ends: info.fire,
            allowSnooze: true,
            alarmID: "",
            firedAt: nil,
            accentHex: currentAccentHex()
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity = current {
            await activity.update(content)
            DiagLog.log("[LA] update id=\(activity.id) -> \(info.title) @ \(info.fire)")
            return
        }

        do {
            let activity = try Activity.request(
                attributes: AlarmActivityAttributes(),
                content: content,
                pushType: nil
            )
            current = activity
            DiagLog.log("[LA] request success id=\(activity.id)")
        } catch {
            DiagLog.log("[LA] request error: \(error)")
        }
    }

    static func markFiredNow() async {
        guard let activity = current else { return }
        var st = activity.content.state
        if st.firedAt == nil { st.firedAt = Date() }
        await activity.update(ActivityContent(state: st, staleDate: nil))
        DiagLog.log("[LA] markFiredNow id=\(activity.id)")
    }

    static func endIfExpired() async {
        guard let activity = current else { return }
        let st = activity.content.state
        if st.ends <= Date() {
            await activity.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            DiagLog.log("[LA] endIfExpired (expired) id=\(activity.id)")
            current = nil
        }
    }

    static func end() async {
        if let activity = current {
            let st = activity.content.state
            await activity.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            DiagLog.log("[LA] end id=\(activity.id)")
            current = nil
        }
    }
}
