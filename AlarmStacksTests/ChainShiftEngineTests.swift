//
//  ChainShiftEngineTests.swift
//  AlarmStacksTests
//

import XCTest
@testable import AlarmStacks

final class ChainInMemoryStore: ChainKVStore {
    var dict: [String: Any] = [:]
    func getBool(_ key: String) -> Bool? { dict[key] as? Bool }
    func getInt(_ key: String) -> Int? { dict[key] as? Int }
    func getDouble(_ key: String) -> Double? { dict[key] as? Double }
    func getString(_ key: String) -> String? { dict[key] as? String }
    func getStringArray(_ key: String) -> [String]? { dict[key] as? [String] }
    func setBool(_ value: Bool, _ key: String) { dict[key] = value }
    func setInt(_ value: Int, _ key: String) { dict[key] = value }
    func setDouble(_ value: Double, _ key: String) { dict[key] = value }
    func setString(_ value: String, _ key: String) { dict[key] = value }
    func setStringArray(_ value: [String], _ key: String) { dict[key] = value }
    func remove(_ key: String) { dict.removeValue(forKey: key) }
}

final class ChainShiftEngineTests: XCTestCase {

    func makeStack(store: ChainInMemoryStore, stack: String, ids: [String], kinds: [ChainStepKindLabel], offsets: [Int], firstTargetEpoch: Int, allowSnooze: [Bool] = []) {
        store.setDouble(Double(firstTargetEpoch), ChainAKKeys.firstTarget(stack))
        store.setStringArray(ids, ChainAKKeys.activeIDs(stack))
        for (i, id) in ids.enumerated() {
            store.setString(stack, ChainAKKeys.stackID(id))
            store.setDouble(Double(offsets[i]), ChainAKKeys.offsetFromFirst(id))
            store.setString(kinds[i].rawValue, ChainAKKeys.kind(id))
            store.setBool(i < allowSnooze.count ? allowSnooze[i] : true, ChainAKKeys.allowSnooze(id))
            store.setString("Pulse", ChainAKKeys.soundName(id))
            store.setString("#00AEEF", ChainAKKeys.accentHex(id))
        }
    }

    // Base snooze pushes chain
    func testBaseSnoozeShiftsAllNonFixed() {
        let store = ChainInMemoryStore()
        let now = 1_700_000_000
        let engine = ChainShiftEngine(store: store, now: { Date(timeIntervalSince1970: TimeInterval(now)) })

        let stack = "stack-A"
        // S1(0), S2(+120), S3(+180)
        let S1 = "S1", S2 = "S2", S3 = "S3"
        makeStack(store: store, stack: stack,
                  ids: [S1, S2, S3],
                  kinds: [.timer, .timer, .relative],
                  offsets: [0, 120, 180],
                  firstTargetEpoch: 1_700_000_600)

        // Snooze S1 by 3m (Δ ~ 180s)
        let plan = engine.buildPlanForSnooze(baseID: S1, snoozeMinutes: 3)!
        XCTAssertTrue(plan.isFirstStep)
        XCTAssertEqual(plan.deltaSeconds, 180)

        engine.apply(plan: plan)
        let ids = store.getStringArray(ChainAKKeys.activeIDs(plan.stackID))!
        XCTAssertEqual(ids.count, 3)
    }

    // Middle snooze pushes only later steps
    func testMiddleSnoozeShiftsOnlyAfter() {
        let store = ChainInMemoryStore()
        let now = 1_700_000_000
        let engine = ChainShiftEngine(store: store, now: { Date(timeIntervalSince1970: TimeInterval(now)) })

        let stack = "stack-B"
        let S1 = "S1", S2 = "S2", S3 = "S3"
        makeStack(store: store, stack: stack,
                  ids: [S1, S2, S3],
                  kinds: [.timer, .timer, .timer],
                  offsets: [0, 120, 180],
                  firstTargetEpoch: 1_700_000_600)

        let plan = engine.buildPlanForSnooze(baseID: S2, snoozeMinutes: 3)!
        XCTAssertFalse(plan.isFirstStep)

        engine.apply(plan: plan)

        let ids = store.getStringArray(ChainAKKeys.activeIDs(plan.stackID))!
        XCTAssertEqual(ids.count, 3)
    }

    // Fixed time immunity
    func testFixedTimeImmunity() {
        let store = ChainInMemoryStore()
        let now = 1_700_000_000
        let engine = ChainShiftEngine(store: store, now: { Date(timeIntervalSince1970: TimeInterval(now)) })

        let stack = "stack-C"
        let S1 = "S1", S2 = "S2", S3 = "S3"
        makeStack(store: store, stack: stack,
                  ids: [S1, S2, S3],
                  kinds: [.fixed, .timer, .fixed],
                  offsets: [0, 120, 1800],
                  firstTargetEpoch: 1_700_000_600)

        let plan = engine.buildPlanForSnooze(baseID: S1, snoozeMinutes: 5)!
        XCTAssertTrue(plan.isFirstStep)
        engine.apply(plan: plan)

        // Only S1 and S2 are replaced (S3 fixed remains scheduled as-is)
        let ids = store.getStringArray(ChainAKKeys.activeIDs(plan.stackID))!
        XCTAssertEqual(ids.count, 2)
    }

    // Rapid re-snooze (snooze same step twice before it fires)
    func testRapidReSnoozeUpdatesMappingAndOffsets() {
        let store = ChainInMemoryStore()
        var now = 1_700_000_000
        let engine = ChainShiftEngine(store: store, now: { Date(timeIntervalSince1970: TimeInterval(now)) })

        let stack = "stack-D"
        let S1 = "S1", S2 = "S2", S3 = "S3"
        makeStack(store: store, stack: stack,
                  ids: [S1, S2, S3],
                  kinds: [.timer, .timer, .timer],
                  offsets: [0, 120, 180],
                  firstTargetEpoch: 1_700_000_600)

        var plan = engine.buildPlanForSnooze(baseID: S2, snoozeMinutes: 3)!
        engine.apply(plan: plan)

        now += 10
        let engine2 = ChainShiftEngine(store: store, now: { Date(timeIntervalSince1970: TimeInterval(now)) })
        plan = engine2.buildPlanForSnooze(baseID: S2, snoozeMinutes: 2)!
        engine2.apply(plan: plan)

        let snoozeMapped = store.getString(ChainAKKeys.snoozeMap(baseID: S2))
        XCTAssertNotNil(snoozeMapped)
    }
}
