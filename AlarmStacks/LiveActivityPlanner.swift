//
//  LiveActivityPlanner.swift
//  AlarmKit
//
//  Created by . . on 8/16/25.
//

import Foundation

/// Plans prearm attempts for a given effective target time.
/// - Ensures attempts fire early enough to avoid ActivityKit's late-start window.
/// - Avoids the final protected window right before the target.
/// - Provides multiple staggered attempts to improve reliability on background/locked devices.
public struct LiveActivityPlanner {

    /// Hard minimum lead time before the effective target that we will *attempt* a request.
    /// Any attempt scheduled with less lead than this will be dropped proactively.
    ///
    /// Rationale:
    /// Logs showed repeated `[ACT] start FAILED ... error=targetMaximumExceeded` when attempting at ~29s.
    /// We enforce a ≥ 48s floor to stay clear of the OS's late-start guardrails.
    public static let hardMinimumLeadSeconds: TimeInterval = 48

    /// Offsets (in seconds) *before* the effective target at which we plan to prearm the Live Activity.
    /// Order matters: earlier attempts come first. Do not include values below `hardMinimumLeadSeconds`.
    ///
    /// Previous plan `[28, 48]` routinely hit `targetMaximumExceeded`. This shifts earlier and adds redundancy.
    public static let attemptOffsetsSeconds: [TimeInterval] = [120, 90, 60, 48]

    /// If an attempt would fall into the last `protectedWindowBeforeTargetSeconds` before target,
    /// it is considered unsafe and will be dropped.
    public static let protectedWindowBeforeTargetSeconds: TimeInterval = 45

    /// If an attempt would land within this many seconds of the next wall-clock minute,
    /// nudge it earlier by `minuteBoundaryNudgeSeconds` to avoid platform scheduling quiescence.
    public static let minuteBoundaryGuardSeconds: TimeInterval = 5
    public static let minuteBoundaryNudgeSeconds: TimeInterval = 2

    /// Compute concrete attempt times for a target, filtering and normalizing as described above.
    /// - Parameters:
    ///   - effTarget: the effective fire time we want the LA ready for
    ///   - now: current clock (passed for testability)
    /// - Returns: strictly ascending list of attempt `Date`s in the future (≥ now)
    public static func plannedAttempts(for effTarget: Date, now: Date = .now) -> [Date] {
        let basePlan = attemptOffsetsSeconds
            .map { effTarget.addingTimeInterval(-$0) }
            .map { adjustForMinuteBoundary($0) }

        // Filter out attempts that are already in the past or too close to target.
        let filtered = basePlan.filter { candidate in
            candidate >= now &&
            effTarget.timeIntervalSince(candidate) >= hardMinimumLeadSeconds &&
            effTarget.timeIntervalSince(candidate) >= protectedWindowBeforeTargetSeconds
        }

        // Ensure the list is strictly ascending (oldest first)
        return filtered.sorted()
    }

    /// Given a candidate attempt time, if it's inside the minute-boundary guard,
    /// nudge it earlier slightly to avoid OS scheduling quiet zones.
    private static func adjustForMinuteBoundary(_ t: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let second = cal.component(.second, from: t)
        if second >= (60 - Int(minuteBoundaryGuardSeconds)) {
            return t.addingTimeInterval(-minuteBoundaryNudgeSeconds)
        }
        return t
    }
}
