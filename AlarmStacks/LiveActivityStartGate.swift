//
//  LiveActivityStartGate.swift
//  AlarmStacks
//
//  Created by . . on 8/24/25.
//

import Foundation
import ActivityKit

@MainActor
enum LiveActivityStartGate {
    // One LA per stack
    private static var activities: [String: Activity<AlarmActivityAttributes>] = [:]

    /// Create or update the Lock-Screen Live Activity for a stack.
    static func upsert(
        state: AlarmActivityAttributes.ContentState,
        isTerminal: Bool,
        grace: TimeInterval = 30
    ) async {
        let attrs = AlarmActivityAttributes(stackID: state.stackName)
        let staleBase = state.firedAt ?? state.ends
        let content = ActivityContent(
            state: state,
            staleDate: staleBase.addingTimeInterval(grace)
        )

        if let act = activities[state.stackName] {
            await act.update(content)
            if isTerminal {
                await act.end(content, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
                activities[state.stackName] = nil
            }
        } else {
            if let act = try? Activity<AlarmActivityAttributes>.request(
                attributes: attrs,
                content: content,
                pushType: nil
            ) {
                activities[state.stackName] = act
                if isTerminal {
                    await act.end(content, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
                    activities[state.stackName] = nil
                }
            }
        }
    }

    /// End and clear if it exists.
    static func endIfExists(
        forStack stackName: String,
        finalState: AlarmActivityAttributes.ContentState,
        grace: TimeInterval = 5
    ) async {
        guard let act = activities[stackName] else { return }
        let content = ActivityContent(
            state: finalState,
            staleDate: (finalState.firedAt ?? finalState.ends).addingTimeInterval(grace)
        )
        await act.end(content, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
        activities[stackName] = nil
    }

    static func drainPendingIfAny() async { /* optional hook */ }
}
