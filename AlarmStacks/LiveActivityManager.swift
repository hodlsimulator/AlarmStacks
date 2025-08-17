//
//  LiveActivityManager.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
enum LiveActivityManager {

    #if canImport(ActivityKit)
    private static var current: Activity<AlarmActivityAttributes>?
    private static var lastState: AlarmActivityAttributes.ContentState?
    #endif

    // MARK: - Next-step computation

    private static func nextStepInfo(for stack: Stack, calendar: Calendar) -> (title: String, fire: Date)? {
        var base = Date()
        var firstTitle: String?
        var firstDate: Date?

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
                firstTitle = step.title
                firstDate  = f
            }
        }
        if let t = firstTitle, let f = firstDate { return (t, f) }
        return nil
    }

    // MARK: - Public API (iOS 16.2+ ActivityKit only)

    static func start(for stack: Stack, calendar: Calendar = .current) async {
        guard let info = nextStepInfo(for: stack, calendar: calendar) else {
            NextAlarmBridge.clear()
            #if canImport(ActivityKit)
            if let activity = current {
                let st = lastState ?? activity.content.state
                await activity.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                current = nil; lastState = nil
            }
            #endif
            return
        }

        // Widget bridge
        NextAlarmBridge.write(.init(stackName: stack.name, stepTitle: info.title, fireDate: info.fire))

        #if canImport(ActivityKit)
        let enabled = (UserDefaults.standard.object(forKey: "debug.liveActivitiesEnabled") as? Bool) ?? true
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Adopt a single existing activity; end extras to avoid stacking.
        if current == nil {
            let existing = Activity<AlarmActivityAttributes>.activities
            if let first = existing.first { current = first }
            for extra in existing.dropFirst() {
                let st = extra.content.state
                await extra.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            }
        }

        // New state/content — ensure firedAt is nil (we haven’t rung yet)
        let newState = AlarmActivityAttributes.ContentState(
            stackName: stack.name,
            stepTitle: info.title,
            ends: info.fire,
            allowSnooze: true,
            alarmID: "",
            firedAt: nil
        )
        let content = ActivityContent(state: newState, staleDate: nil)

        do {
            if let activity = current {
                await activity.update(content)
            } else {
                current = try Activity.request(attributes: AlarmActivityAttributes(),
                                               content: content,
                                               pushType: nil)
            }
            lastState = newState
        } catch {
            // ignored
        }
        #endif
    }

    /// Mark the activity as fired *now* (sets `firedAt`), so UI shows the ring time and never counts up.
    static func markFiredNow() async {
        #if canImport(ActivityKit)
        guard let activity = current else { return }
        var st = lastState ?? activity.content.state
        if st.firedAt == nil { st.firedAt = Date() }
        let content = ActivityContent(state: st, staleDate: nil)
        await activity.update(content)
        lastState = st
        #endif
    }

    /// End the Live Activity if its scheduled time has passed (used when app returns to foreground).
    static func endIfExpired() async {
        #if canImport(ActivityKit)
        guard let activity = current else { return }
        let st = activity.content.state
        if st.ends <= Date() {
            await activity.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            current = nil; lastState = nil
        }
        #endif
    }

    static func end() async {
        NextAlarmBridge.clear()
        #if canImport(ActivityKit)
        if let activity = current {
            let st = lastState ?? activity.content.state
            await activity.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            current = nil; lastState = nil
        }
        #endif
    }
}
