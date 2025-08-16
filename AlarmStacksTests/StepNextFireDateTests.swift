//
//  StepNextFireDateTests.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import XCTest
@testable import AlarmStacks

final class StepNextFireDateTests: XCTestCase {

    // Europe/Dublin (handles DST). Use Gregorian.
    private func makeCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Dublin")!
        cal.locale = Locale(identifier: "en_IE")
        return cal
    }

    private func makeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int = 0, cal: Calendar) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = h; comps.minute = min; comps.second = s
        comps.timeZone = cal.timeZone
        return cal.date(from: comps)!
    }

    // MARK: - Fixed time (no weekdays)

    func testFixedTime_TodayBeforeTime_NoWeekday() throws {
        let cal = makeCalendar()
        let base = makeDate(2025, 1, 15, 6, 0, cal: cal)

        let step = Step(title: "Wake", kind: .fixedTime, order: 0, hour: 7, minute: 30, stack: nil)
        let next = try step.nextFireDate(basedOn: base, calendar: cal)

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 15) // same day
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertTrue(next > base)
    }

    func testFixedTime_TodayAfterTime_NoWeekday() throws {
        let cal = makeCalendar()
        let base = makeDate(2025, 1, 15, 20, 0, cal: cal)

        let step = Step(title: "Evening", kind: .fixedTime, order: 0, hour: 19, minute: 0, stack: nil)
        let next = try step.nextFireDate(basedOn: base, calendar: cal)

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 16) // tomorrow
        XCTAssertEqual(comps.hour, 19)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertTrue(next > base)
    }

    // MARK: - Fixed time + weekdays

    func testFixedTime_WeekdaySelection_PicksSoonest() throws {
        let cal = makeCalendar()
        // Monday 2025-01-13 06:00
        let base = makeDate(2025, 1, 13, 6, 0, cal: cal)

        let step = Step(title: "Gym", kind: .fixedTime, order: 0, hour: 7, minute: 0, stack: nil)
        step.weekdays = [2, 4] // Mon, Wed

        let next = try step.nextFireDate(basedOn: base, calendar: cal)
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: next)

        // Should be Monday (2) at 07:00 since it's still upcoming
        XCTAssertEqual(comps.weekday, 2)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 0)
    }

    // MARK: - DST edge cases (Europe/Dublin)

    func testFixedTime_DSTStart_Missing0230Handled() throws {
        let cal = makeCalendar()
        // DST 2025 starts on Sun 30 Mar 2025 in Europe/Dublin.
        // Base: that day 00:00
        let base = makeDate(2025, 3, 30, 0, 0, cal: cal)

        let step = Step(title: "Spring Forward", kind: .fixedTime, order: 0, hour: 2, minute: 30, stack: nil)
        let next = try step.nextFireDate(basedOn: base, calendar: cal)

        // Accept either 03:30 on the same Sunday (if system shifts forward)
        // or 02:30 the next day (if system moves to the next valid 02:30).
        let c = cal.dateComponents([.year,.month,.day,.hour,.minute], from: next)

        let sameDayShifted = (c.year == 2025 && c.month == 3 && c.day == 30 && c.hour == 3 && c.minute == 30)
        let nextDayExact    = (c.year == 2025 && c.month == 3 && c.day == 31 && c.hour == 2 && c.minute == 30)

        XCTAssertTrue(sameDayShifted || nextDayExact, "Got \(c), expected 03:30 same day or 02:30 next day")
        XCTAssertTrue(next > base)
    }

    func testFixedTime_DSTEnd_Ambiguous0130ChoosesFirstOccurrence() throws {
        let cal = makeCalendar()
        // DST 2025 ends on Sun 26 Oct 2025 in Europe/Dublin.
        // Base: that day 00:00
        let base = makeDate(2025, 10, 26, 0, 0, cal: cal)

        let step = Step(title: "Fall Back", kind: .fixedTime, order: 0, hour: 1, minute: 30, stack: nil)
        let next = try step.nextFireDate(basedOn: base, calendar: cal)

        // Expect 01:30 on the same day (the first occurrence).
        let c = cal.dateComponents([.year,.month,.day,.hour,.minute], from: next)
        XCTAssertEqual(c.year, 2025)
        XCTAssertEqual(c.month, 10)
        XCTAssertEqual(c.day, 26)
        XCTAssertEqual(c.hour, 1)
        XCTAssertEqual(c.minute, 30)
        XCTAssertTrue(next > base)
    }

    // MARK: - Timer

    func testTimer_SimpleAddsDuration() throws {
        let cal = makeCalendar()
        let base = makeDate(2025, 2, 1, 12, 0, cal: cal)

        let step = Step(title: "Focus", kind: .timer, order: 0, durationSeconds: 45 * 60, stack: nil)
        let next = try step.nextFireDate(basedOn: base, calendar: cal)

        let expect = makeDate(2025, 2, 1, 12, 45, cal: cal)
        XCTAssertEqual(next, expect)
    }

    func testTimer_Every2DaysAlignment() throws {
        let cal = makeCalendar()
        // Base: 2025-01-01 10:00
        let base = makeDate(2025, 1, 1, 10, 0, cal: cal)

        // 60m candidate still Jan 1, cadence=every 2 days → should remain Jan 1.
        let step1 = Step(title: "Short", kind: .timer, order: 0, durationSeconds: 60 * 60, everyNDays: 2, stack: nil)
        let next1 = try step1.nextFireDate(basedOn: base, calendar: cal)
        XCTAssertEqual(next1, makeDate(2025, 1, 1, 11, 0, cal: cal))

        // 20h candidate rolls into Jan 2; every 2 days since Jan 1 → should bump to Jan 3 (preserve time-of-day).
        let step2 = Step(title: "Long", kind: .timer, order: 0, durationSeconds: 20 * 60 * 60, everyNDays: 2, stack: nil)
        let next2 = try step2.nextFireDate(basedOn: base, calendar: cal)
        let comps2 = cal.dateComponents([.year,.month,.day,.hour,.minute], from: next2)
        XCTAssertEqual(comps2.year, 2025)
        XCTAssertEqual(comps2.month, 1)
        XCTAssertEqual(comps2.day, 3)
        XCTAssertEqual(comps2.hour, 6) // 10:00 + 20h = 06:00 next day (Jan 2), then aligned to Jan 3 06:00
        XCTAssertEqual(comps2.minute, 0)
    }

    // MARK: - Relative

    func testRelativeToPrev_AddsOffset() throws {
        let cal = makeCalendar()
        let base = makeDate(2025, 5, 10, 9, 15, cal: cal)

        let step = Step(title: "After Prev", kind: .relativeToPrev, order: 1, offsetSeconds: 10 * 60, stack: nil)
        let next = try step.nextFireDate(basedOn: base, calendar: cal)

        let expect = makeDate(2025, 5, 10, 9, 25, cal: cal)
        XCTAssertEqual(next, expect)
    }
}
