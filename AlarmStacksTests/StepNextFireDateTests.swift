//
//  StepNextFireDateTests.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import XCTest
@testable import AlarmStacks

final class StepNextFireDateTests: XCTestCase {

    private func cal(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(identifier: tz) ?? .current
        return c
    }

    func testTimerAddsDuration() throws {
        let c = cal("America/Los_Angeles")
        let base = ISO8601DateFormatter().date(from: "2024-01-15T10:00:00Z")!
        let step = Step(title: "T", kind: .timer, order: 0, durationSeconds: 600)
        let fire = try step.nextFireDate(basedOn: base, calendar: c)
        XCTAssertEqual(fire.timeIntervalSince(base), 600, accuracy: 1.0)
    }

    func testRelativeAddsOffset() throws {
        let c = cal("America/Los_Angeles")
        let base = ISO8601DateFormatter().date(from: "2024-01-15T10:00:00Z")!
        let step = Step(title: "R", kind: .relativeToPrev, order: 0, offsetSeconds: 300)
        let fire = try step.nextFireDate(basedOn: base, calendar: c)
        XCTAssertEqual(fire.timeIntervalSince(base), 300, accuracy: 1.0)
    }

    func testFixedNextTodayOrTomorrow() throws {
        let c = cal("America/Los_Angeles")
        // Base 06:00 local; schedule 06:30 -> same day
        var comps = DateComponents(year: 2024, month: 1, day: 10, hour: 6, minute: 0)
        let base = c.date(from: comps)!
        let step = Step(title: "F", kind: .fixedTime, order: 0, hour: 6, minute: 30)
        let fire = try step.nextFireDate(basedOn: base, calendar: c)
        comps.minute = 30
        let expected = c.date(from: comps)!
        XCTAssertEqual(fire.timeIntervalSince(expected), 0, accuracy: 1.0)
    }

    func testFixedAcrossDSTSpringForward() throws {
        let c = cal("America/Los_Angeles") // DST starts 2024-03-10
        // Base on DST day at 01:55; schedule 02:30 (non-existent that day)
        var comps = DateComponents(year: 2024, month: 3, day: 10, hour: 1, minute: 55)
        let base = c.date(from: comps)!
        let step = Step(title: "F", kind: .fixedTime, order: 0, hour: 2, minute: 30)

        let fire = try step.nextFireDate(basedOn: base, calendar: c)

        // Expect NOT the same day (02:30 doesn't exist); should be a future day at 02:30
        let dc = c.dateComponents([.year,.month,.day,.hour,.minute], from: fire)
        XCTAssertEqual(dc.hour, 2)
        XCTAssertEqual(dc.minute, 30)
        XCTAssertNotEqual(dc.day, 10)
    }
}
