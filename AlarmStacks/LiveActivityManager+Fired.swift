//
//  LiveActivityManager+Fired.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

extension LiveActivityManager {
    /// Mark the current activity/activities as 'ringing now' (sets ContentState.firedAt = now).
    @MainActor
    static func markFiredNow() async {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let now = Date()
            for activity in Activity<LAAttributes>.activities {
                var state = activity.content.state
                if state.firedAt == nil {
                    state.firedAt = now
                    let content = ActivityContent(state: state, staleDate: nil)
                    await activity.update(content) // iOS 16.2+ API
                }
            }
        }
        #endif
    }
}
