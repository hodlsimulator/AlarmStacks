//
//  ChainShiftEngine.swift
//  AlarmStacks
//
//  Core logic for snooze + chain-shift using firstTarget(stack) + offsetFromFirst(id)
//  as the single source of truth for *nominal* times. Effective targets are logged
//  separately in ak.effTarget.<id> and never used for chain maths.
//
//  iOS 26-only assumptions, Swift 6 concurrency.
//

import Foundation

// MARK: - Constants

public enum ChainShift {
    public static let minLeadSeconds: Int = 60
    public static let protectedWindowSeconds: Int = 12
}

// MARK: - Step Kind Label (string persisted)

public enum ChainStepKindLabel: String, Codable {
    case fixed
    case timer
    case relative
}

// MARK: - Key/Value Store (typed API to avoid overload ambiguity)

public protocol ChainKVStore {
    func getBool(_ key: String) -> Bool?
    func getInt(_ key: String) -> Int?
    func getDouble(_ key: String) -> Double?
    func getString(_ key: String) -> String?
    func getStringArray(_ key: String) -> [String]?

    func setBool(_ value: Bool, _ key: String)
    func setInt(_ value: Int, _ key: String)
    func setDouble(_ value: Double, _ key: String)
    func setString(_ value: String, _ key: String)
    func setStringArray(_ value: [String], _ key: String)

    func remove(_ key: String)
}

// MARK: - UserDefaults-backed Store

public final class ChainUserDefaultsStore: ChainKVStore {
    private let defaults: UserDefaults

    public init() { self.defaults = .standard }

    // If you ever need an app-group store, construct it on the main actor:
    @MainActor
    public static func withSuite(_ suite: String) -> ChainUserDefaultsStore {
        let s = ChainUserDefaultsStore()
        if let ud = UserDefaults(suiteName: suite) {
            s.defaults.setVolatileDomain(ud.volatileDomain(forName: suite), forName: suite)
        }
        return s
    }

    public func getBool(_ key: String) -> Bool? { defaults.object(forKey: key) as? Bool }
    public func getInt(_ key: String) -> Int? {
        if let n = defaults.object(forKey: key) as? NSNumber { return n.intValue }
        return defaults.object(forKey: key) as? Int
    }
    public func getDouble(_ key: String) -> Double? {
        if let n = defaults.object(forKey: key) as? NSNumber { return n.doubleValue }
        return defaults.object(forKey: key) as? Double
    }
    public func getString(_ key: String) -> String? { defaults.string(forKey: key) }
    public func getStringArray(_ key: String) -> [String]? { defaults.stringArray(forKey: key) }

    public func setBool(_ value: Bool, _ key: String) { defaults.set(value, forKey: key) }
    public func setInt(_ value: Int, _ key: String) { defaults.set(value, forKey: key) }
    public func setDouble(_ value: Double, _ key: String) { defaults.set(value, forKey: key) }
    public func setString(_ value: String, _ key: String) { defaults.set(value, forKey: key) }
    public func setStringArray(_ value: [String], _ key: String) { defaults.set(value, forKey: key) }

    public func remove(_ key: String) { defaults.removeObject(forKey: key) }
}

// MARK: - Keys (unique namespace)

public enum ChainAKKeys {
    // Per-alarm id
    public static func effTarget(_ id: String) -> String { "ak.effTarget.\(id)" }            // effective (timer) target; diagnostics ONLY
    public static func snoozeMinutes(_ id: String) -> String { "ak.snoozeMinutes.\(id)" }
    public static func stackID(_ id: String) -> String { "ak.stackID.\(id)" }
    public static func offsetFromFirst(_ id: String) -> String { "ak.offsetFromFirst.\(id)" } // seconds (Double preferred)
    public static func kind(_ id: String) -> String { "ak.kind.\(id)" }                       // "fixed" | "timer" | "relative"
    public static func allowSnooze(_ id: String) -> String { "ak.allowSnooze.\(id)" }
    public static func isSnoozeAlarm(_ id: String) -> String { "ak.isSnooze.\(id)" }
    public static func stackName(_ id: String) -> String { "ak.stackName.\(id)" }
    public static func stepTitle(_ id: String) -> String { "ak.stepTitle.\(id)" }
    public static func soundName(_ id: String) -> String { "ak.soundName.\(id)" }
    public static func accentHex(_ id: String) -> String { "ak.accentHex.\(id)" }

    // Stack-level
    public static func firstTarget(_ stackID: String) -> String { "ak.firstTarget.\(stackID)" }  // epoch seconds (Double)
    public static func activeIDs(_ stackID: String) -> String { "alarmkit.ids.\(stackID)" }

    // Snooze mapping
    public static func snoozeMap(baseID: String) -> String { "ak.snooze.map.\(baseID)" } // base -> current snooze id
}

// MARK: - Diagnostics (lightweight)

public enum ChainDiag {
    @inline(__always)
    public static func summary(stack: String, base: String, newBaseLocal: String, delta: Int, baseOffset: Int, isFirst: Bool) {
        print("[CHAIN] shift stack=\(stack) base=\(base) newBase=\(newBaseLocal) Δ=\(delta)s baseOffset=\(baseOffset)s isFirst=\(isFirst ? "y" : "n")")
    }
    @inline(__always)
    public static func resched(newID: String, prev: String, newOffset: Int, newTargetLocal: String, enforcedLead: Int?, kind: ChainStepKindLabel, allowSnooze: Bool) {
        let lead = enforcedLead != nil ? "\(enforcedLead!)" : "-"
        print("[CHAIN] resched id=\(newID) prev=\(prev) newOffset=\(newOffset)s newTarget=\(newTargetLocal) enforcedLead=\(lead) kind=\(kind.rawValue) allowSnooze=\(allowSnooze)")
    }
}

// MARK: - Results

public struct ChainRescheduleItem: Sendable {
    public let oldID: String
    public let newID: String
    public let stackID: String
    public let newOffsetFromFirst: Int        // seconds, nominal offset
    public let nominalTargetEpoch: Int        // seconds since 1970
    public let effectiveTargetEpoch: Int      // seconds since 1970 (after lead/protected enforcement)
    public let enforcedLeadSeconds: Int?      // nil = no enforcement
    public let kind: ChainStepKindLabel
    public let allowSnooze: Bool
}

public struct ChainShiftPlan: Sendable {
    public let stackID: String
    public let baseID: String
    public let isFirstStep: Bool
    public let deltaSeconds: Int
    public let newBaseEffectiveEpoch: Int
    public let baseOldOffset: Int
    public let cancelIDs: [String]
    public let schedules: [ChainRescheduleItem]
}

// MARK: - Adapter protocol (unique name)

public protocol ChainAlarmSchedulingAdapter {
    func cancelAlarm(id: String)
    func scheduleAlarm(id: String, epochSeconds: Int, soundName: String?, accentHex: String?, allowSnooze: Bool)
}

// MARK: - Engine

public final class ChainShiftEngine {

    private let store: ChainKVStore
    private let nowProvider: () -> Date

    public init(store: ChainKVStore, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.nowProvider = now
    }

    // MARK: - Public: Build + Apply Plan

    public func buildPlanForSnooze(baseID: String, snoozeMinutes: Int) -> ChainShiftPlan? {
        guard let stackID = store.getString(ChainAKKeys.stackID(baseID)) else { return nil }
        guard let firstTargetEpoch = store.getDouble(ChainAKKeys.firstTarget(stackID)) else { return nil }
        let baseOffsetD = store.getDouble(ChainAKKeys.offsetFromFirst(baseID)) ?? 0
        let baseOffset = Int(baseOffsetD.rounded())
        let kindRaw = store.getString(ChainAKKeys.kind(baseID)) ?? "timer"
        let _ = ChainStepKindLabel(rawValue: kindRaw) ?? .timer

        let ids = store.getStringArray(ChainAKKeys.activeIDs(stackID)) ?? []

        // Nominal old base time (calendar intent)
        let oldNominalBase = Int(firstTargetEpoch) + baseOffset

        // Snooze effective base time (respect min lead)
        let now = Int(nowProvider().timeIntervalSince1970)
        let desired = now + max(snoozeMinutes * 60, ChainShift.minLeadSeconds)
        let newBaseEffective = desired

        let delta = newBaseEffective - oldNominalBase
        let isFirst = (baseOffset == 0)

        var cancelIDs: [String] = [baseID]
        if let existingSnoozeID = store.getString(ChainAKKeys.snoozeMap(baseID: baseID)) {
            cancelIDs.append(existingSnoozeID)
        }

        // Create snooze alarm (always allows snoozing)
        let snoozeID = UUID().uuidString
        let newBaseOffset = isFirst ? 0 : (baseOffset + delta)

        let nominalForSnooze: Int = isFirst ? newBaseEffective : Int(firstTargetEpoch) + newBaseOffset
        let enforcedLeadForSnooze = max(0, newBaseEffective - now) < ChainShift.minLeadSeconds ? ChainShift.minLeadSeconds : nil

        var out: [ChainRescheduleItem] = []
        out.append(
            ChainRescheduleItem(
                oldID: baseID,
                newID: snoozeID,
                stackID: stackID,
                newOffsetFromFirst: newBaseOffset,
                nominalTargetEpoch: nominalForSnooze,
                effectiveTargetEpoch: newBaseEffective,
                enforcedLeadSeconds: enforcedLeadForSnooze,
                kind: .timer,
                allowSnooze: true
            )
        )

        // Reschedule others
        for old in ids {
            if old == baseID { continue }
            let kindString = store.getString(ChainAKKeys.kind(old)) ?? "timer"
            guard let kind = ChainStepKindLabel(rawValue: kindString) else { continue }
            if kind == .fixed { continue }

            let oldOffsetD = store.getDouble(ChainAKKeys.offsetFromFirst(old)) ?? 0
            let oldOffset = Int(oldOffsetD.rounded())
            let afterBase = oldOffset > baseOffset

            var newOffset = oldOffset
            if isFirst {
                newOffset = oldOffset // offsets unchanged; firstTarget shifts
            } else {
                if afterBase { newOffset = oldOffset + delta }
            }

            let nominal = (isFirst ? newBaseEffective : Int(firstTargetEpoch)) + newOffset

            let secondsUntil = nominal - now
            let effective: Int
            var enforcedLead: Int? = nil
            if secondsUntil < ChainShift.minLeadSeconds {
                effective = now + ChainShift.minLeadSeconds
                enforcedLead = ChainShift.minLeadSeconds
            } else {
                effective = nominal
            }

            let newID = UUID().uuidString
            let allow = store.getBool(ChainAKKeys.allowSnooze(old)) ?? true

            out.append(
                ChainRescheduleItem(
                    oldID: old,
                    newID: newID,
                    stackID: stackID,
                    newOffsetFromFirst: newOffset,
                    nominalTargetEpoch: nominal,
                    effectiveTargetEpoch: effective,
                    enforcedLeadSeconds: enforcedLead,
                    kind: kind,
                    allowSnooze: allow
                )
            )
        }

        return ChainShiftPlan(
            stackID: stackID,
            baseID: baseID,
            isFirstStep: isFirst,
            deltaSeconds: delta,
            newBaseEffectiveEpoch: newBaseEffective,
            baseOldOffset: baseOffset,
            cancelIDs: cancelIDs,
            schedules: out
        )
    }

    public func apply(plan: ChainShiftPlan) {
        let localBase = Self.localString(fromEpoch: plan.newBaseEffectiveEpoch)
        ChainDiag.summary(
            stack: plan.stackID,
            base: plan.baseID,
            newBaseLocal: localBase,
            delta: plan.deltaSeconds,
            baseOffset: plan.baseOldOffset,
            isFirst: plan.isFirstStep
        )

        if plan.isFirstStep {
            store.setDouble(Double(plan.newBaseEffectiveEpoch), ChainAKKeys.firstTarget(plan.stackID))
        }

        var ids = store.getStringArray(ChainAKKeys.activeIDs(plan.stackID)) ?? []
        let cancelSet = Set(plan.cancelIDs)
        ids.removeAll { cancelSet.contains($0) }

        for s in plan.schedules {
            if !ids.contains(s.newID) { ids.append(s.newID) }

            store.setString(plan.stackID, ChainAKKeys.stackID(s.newID))
            store.setDouble(Double(s.newOffsetFromFirst), ChainAKKeys.offsetFromFirst(s.newID))
            store.setString(s.kind.rawValue, ChainAKKeys.kind(s.newID))
            store.setBool(s.allowSnooze, ChainAKKeys.allowSnooze(s.newID))
            store.setDouble(Double(s.effectiveTargetEpoch), ChainAKKeys.effTarget(s.newID))

            if let stackName = store.getString(ChainAKKeys.stackName(s.oldID)) {
                store.setString(stackName, ChainAKKeys.stackName(s.newID))
            }
            if let title = store.getString(ChainAKKeys.stepTitle(s.oldID)) {
                store.setString(title, ChainAKKeys.stepTitle(s.newID))
            }
            if let sound = store.getString(ChainAKKeys.soundName(s.oldID)) {
                store.setString(sound, ChainAKKeys.soundName(s.newID))
            }
            if let accent = store.getString(ChainAKKeys.accentHex(s.oldID)) {
                store.setString(accent, ChainAKKeys.accentHex(s.newID))
            }

            if s.oldID == plan.baseID {
                store.setBool(true, ChainAKKeys.isSnoozeAlarm(s.newID))
                store.setString(s.newID, ChainAKKeys.snoozeMap(baseID: plan.baseID))
            }

            let targetLocal = Self.localString(fromEpoch: s.effectiveTargetEpoch)
            ChainDiag.resched(
                newID: s.newID,
                prev: s.oldID,
                newOffset: s.newOffsetFromFirst,
                newTargetLocal: targetLocal,
                enforcedLead: s.enforcedLeadSeconds,
                kind: s.kind,
                allowSnooze: s.allowSnooze
            )

            cleanupPerID(id: s.oldID)
        }

        store.setStringArray(ids, ChainAKKeys.activeIDs(plan.stackID))
    }

    private func cleanupPerID(id: String) {
        store.remove(ChainAKKeys.effTarget(id))
        store.remove(ChainAKKeys.offsetFromFirst(id))
        store.remove(ChainAKKeys.allowSnooze(id))
        store.remove(ChainAKKeys.isSnoozeAlarm(id))
        store.remove(ChainAKKeys.stackID(id))
        store.remove(ChainAKKeys.kind(id))
        store.remove(ChainAKKeys.stackName(id))
        store.remove(ChainAKKeys.stepTitle(id))
        store.remove(ChainAKKeys.soundName(id))
        store.remove(ChainAKKeys.accentHex(id))
    }

    public static func localString(fromEpoch epoch: Int) -> String {
        let dt = Date(timeIntervalSince1970: TimeInterval(epoch))
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateStyle = .none
        f.timeStyle = .medium
        return f.string(from: dt)
    }
}

// MARK: - Central coordinator (single entry used by AppIntents/UI)

public final class ChainSnoozeCoordinator {

    private let engine: ChainShiftEngine
    private let store: ChainKVStore
    private let scheduler: ChainAlarmSchedulingAdapter

    public init(store: ChainKVStore, scheduler: ChainAlarmSchedulingAdapter, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.scheduler = scheduler
        self.engine = ChainShiftEngine(store: store, now: now)
    }

    public func snoozeAndShift(firedID: String, minutes: Int) {
        let baseID = resolveBaseID(forFiredID: firedID)

        // Snooze gating: snooze alarms always allowed; normal steps respect allowSnooze.
        let isSnoozeAlert = store.getBool(ChainAKKeys.isSnoozeAlarm(firedID)) ?? false
        if !isSnoozeAlert {
            let allowed = store.getBool(ChainAKKeys.allowSnooze(baseID)) ?? true
            if !allowed {
                print("[SNOOZE] Ignored: allowSnooze=false for id=\(baseID)")
                return
            }
        }

        guard let plan = engine.buildPlanForSnooze(baseID: baseID, snoozeMinutes: minutes) else {
            print("[SNOOZE] Failed to build plan for id=\(baseID)")
            return
        }

        engine.apply(plan: plan)

        for cid in plan.cancelIDs {
            scheduler.cancelAlarm(id: cid)
        }

        for s in plan.schedules {
            let sound = store.getString(ChainAKKeys.soundName(s.newID))
            let accent = store.getString(ChainAKKeys.accentHex(s.newID))
            scheduler.scheduleAlarm(
                id: s.newID,
                epochSeconds: s.effectiveTargetEpoch,
                soundName: sound,
                accentHex: accent,
                allowSnooze: s.allowSnooze
            )
        }
    }

    private func resolveBaseID(forFiredID id: String) -> String {
        if store.getBool(ChainAKKeys.isSnoozeAlarm(id)) == true,
           let stack = store.getString(ChainAKKeys.stackID(id)) {
            let ids = store.getStringArray(ChainAKKeys.activeIDs(stack)) ?? []
            for candidateBase in ids {
                if store.getString(ChainAKKeys.snoozeMap(baseID: candidateBase)) == id {
                    return candidateBase
                }
            }
        }
        return id
    }
}
