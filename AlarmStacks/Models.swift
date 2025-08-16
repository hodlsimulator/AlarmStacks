//
//  Models.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import SwiftData

// MARK: - StepKind

enum StepKind: Int, Codable, CaseIterable, Sendable {
    case fixedTime        // e.g. 06:30 (optionally a weekday)
    case timer            // e.g. 25 minutes
    case relativeToPrev   // e.g. +10 minutes after previous step
}

// MARK: - Stack

@Model
final class Stack {
    @Attribute(.unique) var id: UUID
    var name: String
    var isArmed: Bool
    var createdAt: Date
    var themeName: String
    var steps: [Step]

    init(
        id: UUID = UUID(),
        name: String,
        isArmed: Bool = false,
        createdAt: Date = .now,
        themeName: String = "LiquidGlass/Blue",
        steps: [Step] = []
    ) {
        self.id = id
        self.name = name
        self.isArmed = isArmed
        self.createdAt = createdAt
        self.themeName = themeName
        self.steps = steps
    }
}

// MARK: - Convenience

extension Stack {
    var sortedSteps: [Step] {
        steps.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            return a.createdAt < b.createdAt
        }
    }

    /// Free tier: 8 steps per stack (repo README).
    var exceedsFreeTierLimits: Bool { sortedSteps.count > 8 }
}

// MARK: - Step

@Model
final class Step {
    @Attribute(.unique) var id: UUID
    var title: String
    var kind: StepKind
    var order: Int
    var isEnabled: Bool
    var createdAt: Date

    // fixedTime: hour/minute (24h). Optional weekday (1...7, Sunday = 1)
    var hour: Int?            // 0...23
    var minute: Int?          // 0...59
    var weekday: Int?         // 1...7 (nil = any day / next occurrence)

    // timer: duration in seconds
    var durationSeconds: Int?

    // relativeToPrev: offset (+/-) in seconds from the previous step time
    var offsetSeconds: Int?

    // Behaviour
    var soundName: String?
    var allowSnooze: Bool
    var snoozeMinutes: Int

    // Inverse inferred by SwiftData (Stack.steps <-> Step.stack)
    var stack: Stack?

    init(
        id: UUID = UUID(),
        title: String,
        kind: StepKind,
        order: Int,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        hour: Int? = nil,
        minute: Int? = nil,
        weekday: Int? = nil,
        durationSeconds: Int? = nil,
        offsetSeconds: Int? = nil,
        soundName: String? = nil,
        allowSnooze: Bool = true,
        snoozeMinutes: Int = 9,
        stack: Stack? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.order = order
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
        self.durationSeconds = durationSeconds
        self.offsetSeconds = offsetSeconds
        self.soundName = soundName
        self.allowSnooze = allowSnooze
        self.snoozeMinutes = snoozeMinutes
        self.stack = stack
    }
}

// MARK: - Scheduling helpers

enum SchedulingError: Error {
    case invalidInputs
}

extension Step {
    /// Returns the next wall-clock `Date` this step should fire at, based on `base`.
    /// - fixedTime: next occurrence of (weekday?, hour, minute)
    /// - timer: base + duration
    /// - relativeToPrev: base + offset
    func nextFireDate(basedOn base: Date, calendar: Calendar = .current) throws -> Date {
        switch kind {
        case .timer:
            guard let seconds = durationSeconds, seconds > 0
            else { throw SchedulingError.invalidInputs }
            return base.addingTimeInterval(TimeInterval(seconds))

        case .relativeToPrev:
            guard let delta = offsetSeconds
            else { throw SchedulingError.invalidInputs }
            return base.addingTimeInterval(TimeInterval(delta))

        case .fixedTime:
            guard let hour, let minute else { throw SchedulingError.invalidInputs }
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute

            let start = base
            if let weekday {
                comps.weekday = weekday  // 1 = Sunday
                if let next = calendar.nextDate(
                    after: start,
                    matching: comps,
                    matchingPolicy: .nextTimePreservingSmallerComponents,
                    direction: .forward
                ) { return next }
                throw SchedulingError.invalidInputs
            } else {
                // Today at hour:minute, or tomorrow if already passed
                let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)!
                return today > start ? today : calendar.date(byAdding: .day, value: 1, to: today)!
            }
        }
    }

    /// Kept for clarity; currently equals `snoozeMinutes`.
    /// Annotated @MainActor so accessing Settings in future remains safe.
    @MainActor
    var effectiveSnoozeMinutes: Int {
        snoozeMinutes
    }
}
