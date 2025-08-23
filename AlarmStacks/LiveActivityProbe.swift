//
//  LiveActivityProbe.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation
import ActivityKit

/// One-tap smoke test for ActivityKit. Use from a debug button:
/// `await LiveActivityProbe.run()`
/// It requests a tiny Live Activity, logs the result, and ends it immediately.
enum LiveActivityProbe {

    struct ProbeAttributes: ActivityAttributes {
        public struct ContentState: Codable, Hashable {
            var ends: Date
        }
    }

    @MainActor
    static func run() async {
        let info = ActivityAuthorizationInfo()
        let enabled = info.areActivitiesEnabled

        var requestOK = false
        var errorText = "-"
        var startedButNotListed = false

        if enabled {
            do {
                let state = ProbeAttributes.ContentState(ends: Date().addingTimeInterval(5))
                let content = ActivityContent(state: state, staleDate: nil)
                let a = try Activity.request(attributes: ProbeAttributes(), content: content, pushType: nil)
                requestOK = true

                // If activities is empty here, log that odd state.
                startedButNotListed = Activity<ProbeAttributes>.activities.isEmpty

                // End immediately to avoid spending budget.
                await a.end(content, dismissalPolicy: .immediate)
            } catch {
                errorText = String(describing: error)
            }
        }

        DiagLog.log("[LA DIAG] time=\(DiagLog.f(Date())) enabled=\(enabled) request.ok=\(requestOK) error=\(errorText) probe.after=\(Activity<ProbeAttributes>.activities.count) our.after=\(Activity<AlarmActivityAttributes>.activities.count) startedButNotListed=\(startedButNotListed)")
    }
}
