//
//  LiveActivityManager+End.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

extension LiveActivityManager {

    /// End any live activity for a specific stack id (String, per your attributes).
    @MainActor
    static func end(forStackID stackID: String) async {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            for activity in Activity<LAAttributes>.activities where activity.attributes.stackID == stackID {
                let finalState = activity.content.state
                let finalContent = ActivityContent(state: finalState, staleDate: nil)
                await activity.end(finalContent, dismissalPolicy: .immediate) // iOS 16.2+ API
            }
        }
        #endif
    }

    /// End all of the app’s live activities.
    @MainActor
    static func endAll() async {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            for activity in Activity<LAAttributes>.activities {
                let finalState = activity.content.state
                let finalContent = ActivityContent(state: finalState, staleDate: nil)
                await activity.end(finalContent, dismissalPolicy: .immediate) // iOS 16.2+ API
            }
        }
        #endif
    }

    /// Back-compat for older call sites.
    @MainActor
    static func end() async { await endAll() }
}
