//
//  LiveActivityManager+End.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
import ActivityKit

extension LiveActivityManager {

    /// End any live activity for a specific stack id (String, per your attributes).
    @MainActor
    static func end(forStackID stackID: String) async {
        for activity in Activity<AlarmActivityAttributes>.activities where activity.attributes.stackID == stackID {
            let finalState = activity.content.state
            let finalContent = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }

    /// End all of the app’s live activities.
    @MainActor
    static func endAll() async {
        for activity in Activity<AlarmActivityAttributes>.activities {
            let finalState = activity.content.state
            let finalContent = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }

    /// Back-compat for older call sites.
    @MainActor
    static func end() async { await endAll() }
}
