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

    // MARK: - Theme access

    /// Read the current theme, preferring standard defaults, falling back to App Group.
    private static func currentThemePayload() -> ThemePayload {
        let std = UserDefaults.standard.string(forKey: "themeName")
        let grp = UserDefaults(suiteName: AppGroups.main)?.string(forKey: "themeName")
        let name = std ?? grp ?? "Default"
        return ThemeMap.payload(for: name)
    }

    /// Validate/normalise a hex string; accepts "#RRGGBB"/"RRGGBB" or with alpha (8).
    private static func cleanHex(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") { t.removeFirst() }
        let hexSet = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        guard (t.count == 6 || t.count == 8), t.unicodeScalars.allSatisfy({ hexSet.contains($0) }) else { return nil }
        return "#\(t.uppercased())"
    }

    /// Extract an accent/tint-looking hex **only from the first level** of ThemePayload.
    private static func firstLevelAccentHex(from theme: ThemePayload) -> String? {
        var anyHex: String?
        let m = Mirror(reflecting: theme)
        for child in m.children {
            guard let raw = child.value as? String, let hx = cleanHex(raw) else { continue }
            if let label = child.label?.lowercased(),
               (label.contains("accent") || label.contains("tint")) {
                return hx
            }
            if anyHex == nil { anyHex = hx }
        }
        return anyHex
    }

    /// Export the app’s accent hex to both Standard and App Group for the intents path.
    private static func exportAccentHexFromCurrentTheme() {
        let theme = currentThemePayload()
        let hex = firstLevelAccentHex(from: theme) ?? "#3A7BFF" // sane default blue
        UserDefaults.standard.set(hex, forKey: "themeAccentHex")
        UserDefaults(suiteName: AppGroups.main)?.set(hex, forKey: "themeAccentHex")
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

        // Theme for initial content + export accent hex for the App Intents flow.
        let theme = currentThemePayload()
        exportAccentHexFromCurrentTheme()

        // Adopt existing activity for this stack, end extras (avoid duplicates)
        let attrs = AlarmActivityAttributes(stackID: stack.id.uuidString)
        if current == nil {
            let existing = Activity<AlarmActivityAttributes>.activities
            if let match = existing.first(where: { $0.attributes.stackID == stack.id.uuidString }) {
                current = match
            }
            for extra in existing where extra.attributes.stackID != stack.id.uuidString {
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
            if let activity = current, activity.attributes.stackID == stack.id.uuidString {
                await activity.update(content)
            } else {
                current = try Activity.request(
                    attributes: attrs,
                    content: content,
                    pushType: nil
                )
            }
            lastState = newState
        } catch {
            // ignore
        }
    }

    /// Mark the activity as fired *now* and keep the theme in sync + re-export accent.
    static func markFiredNow() async {
        guard let activity = current else { return }
        var st = lastState ?? activity.content.state
        if st.firedAt == nil { st.firedAt = Date() }

        let theme = currentThemePayload()
        st.theme = theme
        exportAccentHexFromCurrentTheme()

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

    // MARK: - Reconcile from App Group (used by Stop/Snooze intents)

    /// Rebuild/refresh the LA for a given stack by scanning the App Group state
    /// and selecting the next upcoming alarm (effective target if present).
    static func refreshFromAppGroup(stackID: String) async {
        let ud = UserDefaults.standard

        let ids = ud.stringArray(forKey: "alarmkit.ids.\(stackID)") ?? []
        if ids.isEmpty {
            // Nothing tracked for this stack — end any running activity for it.
            await endActivity(forStackID: stackID)
            return
        }

        // Anchor for offsets (nominal path)
        let firstEpoch = ud.double(forKey: "ak.firstTarget.\(stackID)")
        let now = Date()

        struct Candidate {
            var id: String
            var date: Date
            var stackName: String
            var stepTitle: String
            var allowSnooze: Bool
        }

        var best: Candidate?
        for s in ids {
            guard let uuid = UUID(uuidString: s) else { continue }

            let stackName = ud.string(forKey: "ak.stackName.\(uuid.uuidString)") ?? "Alarm"
            let stepTitle = ud.string(forKey: "ak.stepTitle.\(uuid.uuidString)") ?? "Step"
            let allow     = (ud.object(forKey: "ak.allowSnooze.\(uuid.uuidString)") as? Bool) ?? false

            // Effective first (timer/snooze), otherwise expected, otherwise derive from (first + offset).
            let effEpoch = ud.double(forKey: "ak.effTarget.\(uuid.uuidString)")
            let expEpoch = ud.double(forKey: "ak.expected.\(uuid.uuidString)")
            let off      = (ud.object(forKey: "ak.offsetFromFirst.\(uuid.uuidString)") as? Double)

            let date: Date? = {
                if effEpoch > 0 { return Date(timeIntervalSince1970: effEpoch) }
                if expEpoch > 0 { return Date(timeIntervalSince1970: expEpoch) }
                if firstEpoch > 0, let off = off {
                    return Date(timeIntervalSince1970: firstEpoch + off)
                }
                return nil
            }()

            guard let d = date else { continue }
            // Ignore anything clearly in the past with a small tolerance.
            if d < now.addingTimeInterval(-2) { continue }

            if let b = best {
                if d < b.date { best = Candidate(id: uuid.uuidString, date: d, stackName: stackName, stepTitle: stepTitle, allowSnooze: allow) }
            } else {
                best = Candidate(id: uuid.uuidString, date: d, stackName: stackName, stepTitle: stepTitle, allowSnooze: allow)
            }
        }

        guard let chosen = best else {
            // No future events — end any running activity for the stack.
            await endActivity(forStackID: stackID)
            return
        }

        // Theme & accent export
        let theme = currentThemePayload()
        exportAccentHexFromCurrentTheme()

        // Write widget bridge
        NextAlarmBridge.write(.init(stackName: chosen.stackName, stepTitle: chosen.stepTitle, fireDate: chosen.date))

        // Adopt or create activity for this stack; clear ringing state
        let attrs = AlarmActivityAttributes(stackID: stackID)
        let existing = Activity<AlarmActivityAttributes>.activities
        let activity = existing.first(where: { $0.attributes.stackID == stackID })

        let newState = AlarmActivityAttributes.ContentState(
            stackName: chosen.stackName,
            stepTitle: chosen.stepTitle,
            ends: chosen.date,
            allowSnooze: chosen.allowSnooze,
            alarmID: chosen.id,
            firedAt: nil,                 // ✅ clear 'ringing'
            theme: theme
        )
        let content = ActivityContent(state: newState, staleDate: nil)

        do {
            if let a = activity {
                await a.update(content)
                if current?.id == a.id { lastState = newState }
            } else {
                let req = try Activity.request(attributes: attrs, content: content, pushType: nil)
                current = req
                lastState = newState
            }
        } catch {
            // ignore
        }
    }

    private static func endActivity(forStackID stackID: String) async {
        let existing = Activity<AlarmActivityAttributes>.activities
        for a in existing where a.attributes.stackID == stackID {
            let st = a.content.state
            await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
        }
        if current?.attributes.stackID == stackID {
            current = nil; lastState = nil
        }
        NextAlarmBridge.clear()
    }

    // MARK: - Theme resync (used by ThemeSync.swift)

    /// Recolour running activities to match the current in-app theme.
    /// This keeps LA visuals and the App Intents accent in sync.
    static func resyncThemeForActiveActivities() async {
        let theme = currentThemePayload()

        for activity in Activity<AlarmActivityAttributes>.activities {
            var st = activity.content.state
            if st.theme != theme {
                st.theme = theme
                await activity.update(ActivityContent(state: st, staleDate: nil))
            }
        }

        // Keep our cached state aligned if we’re tracking one
        if let activity = current {
            var st = lastState ?? activity.content.state
            if st.theme != theme {
                st.theme = theme
                lastState = st
            }
        }

        // Refresh the accent export for App Intents.
        exportAccentHexFromCurrentTheme()
    }
}
