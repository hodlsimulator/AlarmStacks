//
//  AlarmController+LAHooks.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation

extension AlarmController {

    /// Call this right after you log:  "AK alerting id=…"
    func la_onAKAlerting(stackID: String, alarmID: String) {
        Task { @MainActor in
            await LiveActivityController.shared.markFired(stackID: stackID, alarmID: alarmID)
        }
    }

    /// Call this right after you log:  "AK STOP id=…"
    func la_onAKStop(stackID: String) {
        Task { @MainActor in
            await LiveActivityController.shared.end(for: stackID)
        }
    }
}
