//
//  LiveActivityManager+Compat.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation
import ActivityKit
import SwiftUI

extension LiveActivityManager {

    /// Re-apply the current theme (from the App Group) to all visible Live Activities.
    /// Use this after a user changes theme, on foreground, or when you notice
    /// the Snooze/Stop controls aren’t adopting your accent.
    @MainActor
    static func resyncThemeForActiveActivities() {
        // Read the cross-target theme name (Group first, then Standard as fallback)
        let groupID = "group.com.hodlsimulator.alarmstacks"
        let udGroup = UserDefaults(suiteName: groupID)
        let themeName = udGroup?.string(forKey: "themeName")
            ?? UserDefaults.standard.string(forKey: "themeName")
            ?? "Default"

        // Build the theme payload used by the Activity views.
        // NOTE: `ThemeMap` / `ThemePayload` must be available to the app target.
        let payload = ThemeMap.payload(for: themeName)

        let acts = Activity<AlarmActivityAttributes>.activities
        guard acts.isEmpty == false else { return }

        for a in acts {
            var st = a.content.state
            st.theme = payload
            Task { @MainActor in
                await a.update(ActivityContent(state: st, staleDate: nil))
            }
        }

        MiniDiag.log("[ACT] theme.resync name=\(themeName) applied=\(acts.count)")
    }
}
