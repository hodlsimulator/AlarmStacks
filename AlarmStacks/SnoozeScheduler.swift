//
//  SnoozeScheduler.swift
//  AlarmStacks
//
//  Created by . . on 8/18/25.
//

import Foundation

#if canImport(AlarmKit)
import AlarmKit

@MainActor
enum SnoozeScheduler {

    /// Schedules a precise AlarmKit snooze timer N minutes from now (≥ 60s lead).
    /// Returns the new AlarmKit alarm identifier (UUID string).
    @discardableResult
    static func scheduleSnooze(
        baseAlarmID: UUID,
        minutes: Int,
        title: String,
        subtitle: String,
        threadKey: String? = nil,
        userInfo: [String: Any] = [:],
        calendar: Calendar = .current
    ) async throws -> String {

        // Map legacy params to our AK path.
        let stackName = title
        let stepTitle = subtitle.isEmpty ? "Snoozed" : subtitle
        let mins = max(1, minutes)

        if let id = await AlarmKitScheduler.shared.scheduleSnooze(
            baseAlarmID: baseAlarmID,
            stackName: stackName,
            stepTitle: stepTitle,
            minutes: mins
        ) {
            return id
        } else {
            throw NSError(
                domain: "AlarmStacks",
                code: 2001,
                userInfo: [NSLocalizedDescriptionKey: "Failed to schedule AlarmKit snooze."]
            )
        }
    }
}

#else

@MainActor
enum SnoozeScheduler {

    /// AlarmKit is not available in this build. Regular UN notifications are intentionally not used.
    @discardableResult
    static func scheduleSnooze(
        baseAlarmID: UUID,
        minutes: Int,
        title: String,
        subtitle: String,
        threadKey: String? = nil,
        userInfo: [String: Any] = [:],
        calendar: Calendar = .current
    ) async throws -> String {
        throw NSError(
            domain: "AlarmStacks",
            code: 2002,
            userInfo: [NSLocalizedDescriptionKey: "AlarmKit is unavailable; snooze via UN is disabled."]
        )
    }
}

#endif
