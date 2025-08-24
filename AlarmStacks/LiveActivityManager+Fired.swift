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

    /// T-0 last resort: if no activity exists at fire time, create one immediately.
    /// Call this from your fire path when you have the full context handy.
    @MainActor
    static func ensureAtFireTimeIfMissing(
        stackID: String,
        stackName: String,
        stepTitle: String,
        scheduledEnds: Date,
        alarmID: String,
        theme: ThemePayload
    ) async {
        if Activity<AlarmActivityAttributes>.activities.isEmpty {
            DiagLog.log("[ACT] markFiredNow() no activity → creating at T0")
            await LAEnsure.ensureAtFireTime(
                stackID: stackID,
                stackName: stackName,
                stepTitle: stepTitle,
                scheduledEnds: scheduledEnds,
                alarmID: alarmID,
                theme: theme
            )
            LAEnsure.logFinalPresence(present: true, reason: "created")
        } else {
            LAEnsure.logFinalPresence(present: true, reason: "updated")
        }
    }
}
