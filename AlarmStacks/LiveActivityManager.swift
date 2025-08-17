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
    // iOS 16.2+ ActivityKit only
    private static var current: Activity<AlarmActivityAttributes>?
    private static var lastState: AlarmActivityAttributes.ContentState?
    #endif

    // Compute the first upcoming step in the stack.
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

    // Start or update the single Live Activity for the next pending step.
    static func start(for stack: Stack, calendar: Calendar = .current) async {
        guard let info = nextStepInfo(for: stack, calendar: calendar) else {
            // No future step — clear widget + end any existing activity with content.
            NextAlarmBridge.clear()
            #if canImport(ActivityKit)
            if let activity = current {
                let st = lastState ?? activity.content.state
                let content = ActivityContent(state: st, staleDate: nil)
                await activity.end(content, dismissalPolicy: .immediate)
                current = nil
                lastState = nil
            }
            #endif
            return
        }

        // Always update the widget (and reload timelines).
        NextAlarmBridge.write(.init(stackName: stack.name, stepTitle: info.title, fireDate: info.fire))

        #if canImport(ActivityKit)
        let laEnabled = (UserDefaults.standard.object(forKey: "debug.liveActivitiesEnabled") as? Bool) ?? true
        guard laEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Adopt an existing activity if present; end extras to avoid stacking (with content).
        if current == nil {
            let existing = Activity<AlarmActivityAttributes>.activities
            if let first = existing.first { current = first }
            for extra in existing.dropFirst() {
                let st = extra.content.state
                await extra.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            }
        }

        // New state/content for the upcoming step
        let newState = AlarmActivityAttributes.ContentState(
            stackName: stack.name,
            stepTitle: info.title,
            ends: info.fire,
            allowSnooze: true,
            alarmID: "" // supply AlarmKit UUID if you track it
        )
        let content = ActivityContent(state: newState, staleDate: nil)

        do {
            if let activity = current {
                await activity.update(content)        // update existing
            } else {
                current = try Activity.request(       // create new
                    attributes: AlarmActivityAttributes(),
                    content: content,
                    pushType: nil
                )
            }
            lastState = newState
        } catch {
            // OK if the OS/user blocks Live Activities.
        }
        #endif
    }

    static func end() async {
        NextAlarmBridge.clear()
        #if canImport(ActivityKit)
        if let activity = current {
            let st = lastState ?? activity.content.state
            let content = ActivityContent(state: st, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            current = nil
            lastState = nil
        }
        #endif
    }
}
