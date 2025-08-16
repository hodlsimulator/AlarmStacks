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
    case fixedTime        // e.g. 06:30 (optionally a weekday or multiple weekdays)
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

    // fixedTime: hour/minute (24h). Repeat on specific weekdays (1...7, Sunday = 1).
    var hour: Int?            // 0...23
    var minute: Int?          // 0...59

    /// Legacy single weekday (kept for compatibility). If `weekdays` is set, it takes precedence.
    var weekday: Int?         // 1...7 (nil = any day / next occurrence)

    /// New: multiple weekdays. If non-empty, restrict fixed-time to these days (1...7; Sunday=1).
    var weekdays: [Int]?      // nil or [] = any day

    // timer: duration in seconds (+ optional cadence)
    var durationSeconds: Int?

    // relativeToPrev: offset (+/-) in seconds from the previous step time
    var offsetSeconds: Int?

    // Behaviour
    var soundName: String?
    var allowSnooze: Bool
    var snoozeMinutes: Int

    /// New: for timer steps, only fire on days where (days since base) % N == 0. Example: N=2 -> every 2 days.
    var everyNDays: Int?      // timers only; >= 1 (nil -> no cadence gating)

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
        everyNDays: Int? = nil,
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
        self.everyNDays = everyNDays
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
    /// - timer: base + duration, then apply optional `everyNDays` gating
    /// - relativeToPrev: base + offset
    ///
    /// P0: Robust for DST / time zone transitions by consistently using `Calendar.nextDate(...)`.
    func nextFireDate(basedOn base: Date, calendar: Calendar = .current) throws -> Date {
        switch kind {
        case .timer:
            guard let seconds = durationSeconds, seconds > 0
            else { throw SchedulingError.invalidInputs }
            let tentative = base.addingTimeInterval(TimeInterval(seconds))
            if let n = everyNDays, n > 1 {
                return alignToEveryNDays(from: base, candidate: tentative, n: n, calendar: calendar)
            }
            return tentative

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

            // No weekday constraints: use nextDate to handle DST-missing times (e.g. 02:30 on spring forward).
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            if let next = calendar.nextDate(
                after: start,
                matching: comps,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                direction: .forward
            ) {
                return next
            }
            throw SchedulingError.invalidInputs
        }
    }

    /// Align the candidate date forward to the next day that satisfies "every N days"
    /// measured from the `base` day boundary, preserving the time-of-day.
    private func alignToEveryNDays(from base: Date, candidate: Date, n: Int, calendar: Calendar) -> Date {
        guard n > 1 else { return candidate }
        let baseDay = calendar.startOfDay(for: base)
        let candDay = calendar.startOfDay(for: candidate)
        let deltaDays = calendar.dateComponents([.day], from: baseDay, to: candDay).day ?? 0
        let mod = ((deltaDays % n) + n) % n
        if mod == 0 { return candidate }
        // Bump forward by the remaining days to land on the cadence.
        return calendar.date(byAdding: .day, value: (n - mod), to: candidate) ?? candidate
    }

    /// Kept for clarity; currently equals `snoozeMinutes`.
    /// Annotated @MainActor so accessing Settings in future remains safe.
    @MainActor
    var effectiveSnoozeMinutes: Int {
        snoozeMinutes
    }
}
