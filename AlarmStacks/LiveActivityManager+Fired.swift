//
//  LiveActivityManager+Fired.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
import ActivityKit

extension LiveActivityManager {
    /// Mark the current activity/activities as 'ringing now' (sets ContentState.firedAt = now).
    @MainActor
    static func markFiredNow() async {
        let now = Date()
        for activity in Activity<AlarmActivityAttributes>.activities {
            var state = activity.content.state
            if state.firedAt == nil {
                state.firedAt = now
                let content = ActivityContent(state: state, staleDate: nil)
                await activity.update(content)
            }
        }
    }
}
