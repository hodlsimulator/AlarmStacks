//
//  Models.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import SwiftData

@Model
final class AlarmStep: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    /// Duration for timer-style steps (seconds). Use 0 for “instant” alarm at a fixed time.
    var durationSeconds: Int
    /// Optional fixed time-of-day (hour/minute) for “alarm” steps; nil means “relative timer”.
    var hour: Int?
    var minute: Int?
    /// Weekday mask for repeating (0-6 = Sun-Sat); empty means one-shot or daily.
    var weekdays: [Int]
    var tintHex: String

    init(
        id: UUID = UUID(),
        title: String,
        durationSeconds: Int,
        hour: Int? = nil,
        minute: Int? = nil,
        weekdays: [Int] = [],
        tintHex: String = "#FF2D55"
    ) {
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.tintHex = tintHex
    }
}

@Model
final class AlarmStack: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var steps: [AlarmStep]

    init(id: UUID = UUID(), name: String, steps: [AlarmStep]) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.steps = steps
    }
}
