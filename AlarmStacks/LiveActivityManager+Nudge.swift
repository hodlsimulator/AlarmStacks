//
//  LiveActivityManager+Nudge.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// A tiny "force refresh" that re-sends existing state to ActivityKit.
/// Useful to nudge lock-screen visibility when content hasn't changed.
extension LiveActivityManager {
    @MainActor
    static func forceRefreshActiveActivities(forStackID stackID: String? = nil) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        for a in Activity<AlarmActivityAttributes>.activities
        where stackID == nil || a.attributes.stackID == stackID {
            let st = a.content.state
            await a.update(ActivityContent(state: st, staleDate: nil))
        }
        #endif
    }
}
