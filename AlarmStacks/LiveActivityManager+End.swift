//
//  LiveActivityManager+End.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
import ActivityKit

extension LiveActivityManager {

    /// End any live activity for a specific stack id.
    /// Adds a short grace so we don't accidentally end *right* before the fire window.
    @MainActor
    static func end(forStackID stackID: String, graceSeconds: TimeInterval = 120) async {
        let now = Date()
        for activity in Activity<AlarmActivityAttributes>.activities where activity.attributes.stackID == stackID {
            let ends = activity.content.state.ends
            if now < ends.addingTimeInterval(graceSeconds) {
                DiagLog.log("[ACT] end.skip (within grace) stack=\(stackID) ends=\(DiagLog.f(ends))")
                continue
            }
            let finalContent = activity.content
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }

    /// End all of the app’s live activities.
    @MainActor
    static func endAll() async {
        for activity in Activity<AlarmActivityAttributes>.activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
    }

    @MainActor
    static func end() async { await endAll() }
}
