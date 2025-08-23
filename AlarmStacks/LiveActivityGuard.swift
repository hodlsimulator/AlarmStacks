//
//  LiveActivityGuard.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation
import ActivityKit

/// Keep Live Activity starts under the system cap and recover from transient failures.
enum LiveActivityGuard {

    /// Keep at most `cap` activities of this attributes type. Ends extras immediately.
    static func enforceCap<A: ActivityAttributes>(for type: A.Type, cap: Int = 1) async {
        let running = Activity<A>.activities
        guard running.count > cap else { return }
        for a in running {
            let content = ActivityContent(state: a.content.state, staleDate: nil)
            await a.end(content, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
        }
    }

    /// Request a Live Activity with a single best-effort retry after cleaning up.
    @discardableResult
    static func requestWithBestEffort<A: ActivityAttributes>(
        for type: A.Type,
        cap: Int = 1,
        _ makeRequest: () throws -> Activity<A>
    ) async throws -> Activity<A> {
        await enforceCap(for: type, cap: cap)
        do {
            return try makeRequest()
        } catch {
            await endAll(type)
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            return try makeRequest()
        }
    }

    static func endAll<A: ActivityAttributes>(_ type: A.Type) async {
        for a in Activity<A>.activities {
            let content = ActivityContent(state: a.content.state, staleDate: nil)
            await a.end(content, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
        }
    }
}
