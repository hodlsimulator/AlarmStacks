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
    case fixedTime        // 06:30 (optionally weekdays)
    case timer            // 25 minutes
    case relativeToPrev   // +10 minutes after previous
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
        themeName: String = "Default",
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

extension Stack {
    var sortedSteps: [Step] {
        steps.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            return a.createdAt < b.createdAt
        }
    }
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

    // fixedTime: hour/minute (24h). Repeat on specific weekdays (1...7, Sunday = 1).
    var hour: Int?            // 0...23
    var minute: Int?          // 0...59

    /// Legacy single weekday. If `weekdays` is non-empty, it takes precedence.
    var weekday: Int?         // 1...7 (nil = any day / next occurrence)

    /// Multiple weekdays. If non-empty, restrict fixed-time to these days (1...7; Sunday=1).
    var weekdays: [Int]?      // nil or [] = any day

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
        weekdays: [Int]? = nil,
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
        self.weekdays = weekdays
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
    /// - fixedTime: next occurrence of (weekdays? OR legacy weekday? OR any day) at hour:minute
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
            let start = base

            // If multi-weekday selection exists, find the earliest next among them.
            if let days = weekdays?.filter({ (1...7).contains($0) }), !days.isEmpty {
                var best: Date?
                for d in days {
                    var comps = DateComponents()
                    comps.weekday = d
                    comps.hour = hour
                    comps.minute = minute
                    if let next = calendar.nextDate(
                        after: start,
                        matching: comps,
                        matchingPolicy: .nextTimePreservingSmallerComponents,
                        direction: .forward
                    ) {
                        if best == nil || next < best! { best = next }
                    }
                }
                if let best { return best }
                throw SchedulingError.invalidInputs
            }

            // Legacy: single weekday
            if let weekday {
                var comps = DateComponents()
                comps.weekday = weekday
                comps.hour = hour
                comps.minute = minute
                if let next = calendar.nextDate(
                    after: start,
                    matching: comps,
                    matchingPolicy: .nextTimePreservingSmallerComponents,
                    direction: .forward
                ) { return next }
                throw SchedulingError.invalidInputs
            }

            // No weekday constraints: today at hour:minute, or tomorrow if already passed
            if let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) {
                return today > start ? today : calendar.date(byAdding: .day, value: 1, to: today)!
            }
            throw SchedulingError.invalidInputs
        }
    }

    @MainActor
    var effectiveSnoozeMinutes: Int { snoozeMinutes }
}
