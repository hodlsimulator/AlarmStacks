//
//  StepSchedulingTests.swift
//  AlarmStacksTests
//
//  Created by . . on 8/16/25.
//

import XCTest
@testable import AlarmStacks

final class StepSchedulingTests: XCTestCase {

    // Helper: Calendar for Los Angeles (DST on/off)
    private func laCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    // Helper to make a date from comps in LA
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = h; comps.minute = min; comps.second = s
        return laCalendar().date(from: comps)!
    }

    func testFixedTime_withoutWeekday_todayBeforeTime_returnsToday() throws {
        // May 1, 2025 05:00 base → fixed 06:30 should be same day 06:30
        let base = date(2025, 5, 1, 5, 0)
        let step = Step(title: "Wake", kind: .fixedTime, order: 0, hour: 6, minute: 30)
        let next = try step.nextFireDate(basedOn: base, calendar: laCalendar())
        let comps = laCalendar().dateComponents([.year, .month, .day, .hour, .minute], from: next)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.hour, 6)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFixedTime_withoutWeekday_afterTime_returnsTomorrow() throws {
        // May 1, 2025 23:59 base → fixed 06:30 should be May 2, 06:30
        let base = date(2025, 5, 1, 23, 59)
        let step = Step(title: "Wake", kind: .fixedTime, order: 0, hour: 6, minute: 30)
        let next = try step.nextFireDate(basedOn: base, calendar: laCalendar())
        let comps = laCalendar().dateComponents([.year, .month, .day, .hour, .minute], from: next)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 2)
        XCTAssertEqual(comps.hour, 6)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFixedTime_withWeekday_acrossDSTStart() throws {
        // DST starts in LA on Mar 9, 2025 (clock jumps 02:00→03:00).
        // Base: Sat Mar 8, 23:00 → next Sunday 06:30 should be Mar 9, 06:30.
        let base = date(2025, 3, 8, 23, 0)
        let step = Step(title: "Wake", kind: .fixedTime, order: 0, hour: 6, minute: 30)
        step.weekday = 1 // Sunday = 1
        let next = try step.nextFireDate(basedOn: base, calendar: laCalendar())
        let comps = laCalendar().dateComponents([.year, .month, .day, .hour, .minute], from: next)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 9)
        XCTAssertEqual(comps.hour, 6)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFixedTime_withWeekday_acrossDSTEnd() throws {
        // DST ends in LA on Nov 2, 2025 (clock repeats 01:00).
        // Base: Sat Nov 1, 23:00 → next Sunday 06:30 should be Nov 2, 06:30 (unambiguous).
        let base = date(2025, 11, 1, 23, 0)
        let step = Step(title: "Wake", kind: .fixedTime, order: 0, hour: 6, minute: 30)
        step.weekday = 1 // Sunday
        let next = try step.nextFireDate(basedOn: base, calendar: laCalendar())
        let comps = laCalendar().dateComponents([.year, .month, .day, .hour, .minute], from: next)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 11)
        XCTAssertEqual(comps.day, 2)
        XCTAssertEqual(comps.hour, 6)
        XCTAssertEqual(comps.minute, 30)
    }

    func testTimerAddsSeconds() throws {
        let base = date(2025, 5, 1, 12, 0)
        let step = Step(title: "Timer", kind: .timer, order: 0, durationSeconds: 90)
        let next = try step.nextFireDate(basedOn: base, calendar: laCalendar())
        let comps = laCalendar().dateComponents([.hour, .minute, .second], from: next)
        XCTAssertEqual(comps.hour, 12)
        XCTAssertEqual(comps.minute, 1)
        XCTAssertEqual(comps.second, 30)
    }

    func testRelativeOffsetCanBeNegative() throws {
        let base = date(2025, 5, 1, 12, 0)
        let step = Step(title: "Back 5m", kind: .relativeToPrev, order: 0, offsetSeconds: -300)
        let next = try step.nextFireDate(basedOn: base, calendar: laCalendar())
        let comps = laCalendar().dateComponents([.hour, .minute, .second], from: next)
        XCTAssertEqual(comps.hour, 11)
        XCTAssertEqual(comps.minute, 55)
        XCTAssertEqual(comps.second, 0)
    }
}
