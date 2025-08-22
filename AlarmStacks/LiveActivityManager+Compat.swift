//
//  LiveActivityManager+Compat.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation

// Back-compat for older call sites.
extension LiveActivityManager {

    /// Called by AlarmKitScheduler when the background agent updates app-group
    /// state for the next/active alarm. Safe to call from any context.
    /// (Kept async so existing `await` call sites compile.)
    static func refreshFromAppGroup() async {
        // If you later add a richer refresh path, call it here.
        // For now we just trigger a visible pass (e.g. theme/tint & any cached state).
        resyncThemeForActiveActivities()
    }
}
