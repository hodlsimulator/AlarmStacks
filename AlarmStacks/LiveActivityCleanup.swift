//
//  LiveActivityCleanup.swift
//  AlarmStacks (App target)
//
//  Created by . . on 8/23/25.
//

import Foundation
import ActivityKit

/// Ends obviously-stale / incomplete Live Activities that can survive reboots
/// (those “clock-only, opaque tiles” with lost state).
@MainActor
func cleanupLiveActivitiesOnLaunch() {
    // If LAs are disabled system-wide, do nothing.
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    // Run asynchronously but remain on the main actor (required by your types).
    Task { @MainActor in
        let activities = Activity<AlarmActivityAttributes>.activities
        var ended = 0

        for activity in activities {
            // iOS 16.2+: `content.state`
            let state = activity.content.state

            // Treat missing identifiers/names as incomplete; also end ones long past their end.
            let missingDetails = state.alarmID.isEmpty || state.stackName.isEmpty || state.stepTitle.isEmpty
            let wayPastEnd     = state.ends < Date().addingTimeInterval(-60)

            if missingDetails || wayPastEnd {
                // iOS 16.2+: end(content:dismissalPolicy:) — async, non-throwing
                await activity.end(activity.content, dismissalPolicy: .immediate)
                ended += 1
            }
        }

        DiagLog.log("[ACT] boot-clean finished ended=\(ended) total=\(activities.count)")
    }
}
