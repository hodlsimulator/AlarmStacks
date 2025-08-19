//
//  LiveActivityManager.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
import SwiftUI
import ActivityKit
import Combine

@MainActor
enum LiveActivityManager {

    private static var current: Activity<AlarmActivityAttributes>?
    private static var lastState: AlarmActivityAttributes.ContentState?

    // MARK: - Theme access (robust against races)
    /// Read the current theme, preferring standard defaults, falling back to App Group.
    private static func currentThemePayload() -> ThemePayload {
        let std = UserDefaults.standard.string(forKey: "themeName")
        let grp = UserDefaults(suiteName: AppGroups.main)?.string(forKey: "themeName")
        let name = std ?? grp ?? "Default"
        return ThemeMap.payload(for: name)
    }

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

    // MARK: - Public API

    static func start(for stack: Stack, calendar: Calendar = .current) async {
        guard let info = nextStepInfo(for: stack, calendar: calendar) else {
            NextAlarmBridge.clear()
            if let activity = current {
                let st = lastState ?? activity.content.state
                await activity.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                current = nil; lastState = nil
            }
            return
        }

        // Widget bridge for the static widget
        NextAlarmBridge.write(.init(stackName: stack.name, stepTitle: info.title, fireDate: info.fire))

        let enabled = (UserDefaults.standard.object(forKey: "debug.liveActivitiesEnabled") as? Bool) ?? true
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Theme for initial content
        let theme = currentThemePayload()

        // Adopt one existing activity; end extras to avoid stacking duplicates
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
            firedAt: nil,
            theme: theme
        )
        let content = ActivityContent(state: newState, staleDate: nil)

        do {
            if let activity = current {
                await activity.update(content)
            } else {
                current = try Activity.request(
                    attributes: AlarmActivityAttributes(),
                    content: content,
                    pushType: nil
                )
            }
            lastState = newState
        } catch {
            // ignore
        }
    }

    /// Mark the activity as fired *now* (sets `firedAt`) and keep the theme in sync.
    static func markFiredNow() async {
        guard let activity = current else { return }
        var st = lastState ?? activity.content.state
        if st.firedAt == nil { st.firedAt = Date() }

        // Refresh theme in case it changed moments before ring
        st.theme = currentThemePayload()

        let content = ActivityContent(state: st, staleDate: nil)
        await activity.update(content)
        lastState = st
    }

    /// End the Live Activity if its scheduled time has passed (used when app returns to foreground).
    static func endIfExpired() async {
        guard let activity = current else { return }
        let st = activity.content.state
        if st.ends <= Date() {
            await activity.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            current = nil; lastState = nil
        }
    }

    static func end() async {
        NextAlarmBridge.clear()
        if let activity = current {
            let st = lastState ?? activity.content.state
            await activity.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
            current = nil; lastState = nil
        }
    }

    /// Call this when theme changes (and at app foreground) to recolour running activities.
    static func resyncThemeForActiveActivities() async {
        let theme = currentThemePayload()

        for activity in Activity<AlarmActivityAttributes>.activities {
            var st = activity.content.state
            if st.theme != theme {
                st.theme = theme
                await activity.update(ActivityContent(state: st, staleDate: nil))
            }
        }

        // Keep our cached state aligned if we’re tracking a current one
        if let activity = current {
            var st = lastState ?? activity.content.state
            if st.theme != theme {
                st.theme = theme
                lastState = st
            }
        }
    }
}
