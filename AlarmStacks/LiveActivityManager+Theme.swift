//
//  LiveActivityManager+Theme.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

extension LiveActivityManager {
    /// Read theme from the app group and push it to active LAs.
    /// Intentionally non-async; per-activity updates are spawned in Tasks.
    static func resyncThemeForActiveActivities() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        let themeName = UserDefaults(suiteName: AppGroups.main)?
            .string(forKey: "themeName") ?? "Default"
        let theme = ThemeMap.payload(for: themeName)

        for activity in Activity<LAAttributes>.activities {
            var state = activity.content.state
            guard state.theme != theme else { continue }
            state.theme = theme
            let content = ActivityContent(state: state, staleDate: nil)
            Task { await activity.update(content) } // iOS 16.2+ API
        }
        #endif
    }

    /// Same as above, but filtered to a specific stack id.
    static func resyncThemeForActiveActivities(forStackID stackID: String) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        let themeName = UserDefaults(suiteName: AppGroups.main)?
            .string(forKey: "themeName") ?? "Default"
        let theme = ThemeMap.payload(for: themeName)

        for activity in Activity<LAAttributes>.activities where activity.attributes.stackID == stackID {
            var state = activity.content.state
            guard state.theme != theme else { continue }
            state.theme = theme
            let content = ActivityContent(state: state, staleDate: nil)
            Task { await activity.update(content) }
        }
        #endif
    }
}
