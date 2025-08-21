//
//  LiveActivityManager+ThemeSync.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//

import Foundation
import ActivityKit

@MainActor
extension LiveActivityManager {

    /// Update any running Live Activities to the current theme accent.
    static func resyncThemeForActiveActivities() async {
        // Read accent hex (prefer Standard, fall back to App Group, then a sane default).
        let stdHex = UserDefaults.standard.string(forKey: "themeAccentHex")
        let grpHex = UserDefaults(suiteName: AppGroups.main)?.string(forKey: "themeAccentHex")
        let accent = stdHex ?? grpHex ?? "#3A7BFF"

        // Keep the App Group copy up-to-date for intents.
        UserDefaults(suiteName: AppGroups.main)?.set(accent, forKey: "themeAccentHex")

        // Push the accent to any running activities.
        for activity in Activity<AlarmActivityAttributes>.activities {
            var state = activity.content.state
            if state.accentHex != accent {
                state.accentHex = accent
                let content = ActivityContent<AlarmActivityAttributes.ContentState>(state: state, staleDate: nil)
                await activity.update(content)
            }
        }
    }
}
