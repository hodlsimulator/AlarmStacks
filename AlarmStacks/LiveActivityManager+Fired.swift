//
//  LiveActivityManager+Fired.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
import ActivityKit

extension LiveActivityManager {
    /// Update **all** active activities to mark them as 'ringing' at the given time.
    /// Prefer `LiveActivityManager.markFiredNow()` from the core manager when you need
    /// the “nearest” activity behaviour. This helper is kept for back-compat.
    @MainActor
    static func markAllActivitiesFired(at date: Date = Date()) async {
        for activity in Activity<AlarmActivityAttributes>.activities {
            var state = activity.content.state
            state.firedAt = date
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }
    }
}
