//
//  LiveActivityManager+AttemptStartNowShims.swift
//  AlarmStacks
//
//  Created by . . on 8/18/25.
//  Purpose: Provide public/async overloads of `attemptStartNow` that match
//  legacy call sites in AlarmKitScheduler (stackID:calendar:) and (stackID:),
//  and a public effTarget-based variant for newer sites.
//

import Foundation

@MainActor
extension LiveActivityManager {

    /// Legacy overload used by AlarmKitScheduler:
    /// `attemptStartNow(stackID:calendar:)`
    ///
    /// We ignore the calendar argument (it wasn’t actually needed to poke the LA).
    /// We pass a generous `nearWindowOverride` so we won't self-cull immediately.
    static func attemptStartNow(stackID: String, calendar _: Calendar) async {
        // 4h window so the ensure() path won’t immediately end the LA due to the far-future guard.
        let overrideWindow: TimeInterval = 4 * 60 * 60
        await LiveActivityManager.shared.sync(
            stackID: stackID,
            reason: "attemptStartNow(calendar:)",
            nearWindowOverride: overrideWindow
        )
    }

    /// Public overload that accepts the effective target time.
    /// Uses `sync` with a window that always encompasses the lead, so far-future culling won’t apply.
    static func attemptStartNow(stackID: String, effTarget: Date) async {
        let lead = max(0, effTarget.timeIntervalSinceNow)
        let overrideWindow = max(lead + 5, 4 * 60 * 60) // cushion past lead
        await LiveActivityManager.shared.sync(
            stackID: stackID,
            reason: "attemptStartNow(effTarget:)",
            nearWindowOverride: overrideWindow
        )
    }

    /// Convenience shim for sites that only pass the stackID.
    static func attemptStartNow(stackID: String) async {
        let overrideWindow: TimeInterval = 4 * 60 * 60
        await LiveActivityManager.shared.sync(
            stackID: stackID,
            reason: "attemptStartNow()",
            nearWindowOverride: overrideWindow
        )
    }
}
