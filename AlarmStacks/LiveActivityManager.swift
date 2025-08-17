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
    @available(iOS 16.1, *)
    private static var current: Activity<AlarmActivityAttributes>?
    @available(iOS 16.1, *)
    private static var lastState: AlarmActivityAttributes.ContentState?
    #endif

    /// Compute the first upcoming step in the stack from "now".
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
                firstDate = f
            }
        }

        if let t = firstTitle, let f = firstDate { return (t, f) }
        return nil
    }

    static func start(for stack: Stack, calendar: Calendar = .current) async {
        guard let info = nextStepInfo(for: stack, calendar: calendar) else { return }

        // Update widget bridge
        NextAlarmBridge.write(.init(stackName: stack.name, stepTitle: info.title, fireDate: info.fire))

        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let attributes = AlarmActivityAttributes()
            let state = AlarmActivityAttributes.ContentState(
                stackName: stack.name,
                stepTitle: info.title,
                ends: info.fire,
                allowSnooze: true,
                alarmID: "" // pass a real AlarmKit UUID string if available
            )

            do {
                if #available(iOS 16.2, *) {
                    let content = ActivityContent(state: state, staleDate: nil)
                    current = try Activity.request(attributes: attributes, content: content, pushType: nil)
                } else {
                    current = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
                }
                lastState = state
            } catch {
                // Ignore failures (user may have Live Activities off)
            }
        }
        #endif
    }

    static func end() async {
        NextAlarmBridge.clear()
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *), let activity = current {
            if #available(iOS 16.2, *) {
                // Prefer the last state we set; fall back to the activity’s current content.state.
                let state = lastState ?? activity.content.state
                let content = ActivityContent(state: state, staleDate: nil)
                await activity.end(content, dismissalPolicy: .immediate)
            } else {
                let state = lastState ?? activity.contentState
                await activity.end(using: state, dismissalPolicy: .immediate)
            }
            current = nil
            lastState = nil
        }
        #endif
    }
}
