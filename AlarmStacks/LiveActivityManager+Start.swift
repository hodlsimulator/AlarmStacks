//
//  LiveActivityManager+Start.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
import ActivityKit
#if canImport(UIKit)
import UIKit
#endif

extension LiveActivityManager {

    // MARK: Public entry points

    /// Call this after you persist App Group keys (don’t gate on visibility).
    @MainActor
    static func ensureFromAppGroup(stackID: String) async {
        await refreshFromGroup(stackID: stackID, excludeID: nil)
    }

    /// Convenience: use if your call sites pass a `Stack` (or anything) instead of a String.
    @MainActor
    static func ensureFromStack(_ maybeStack: Any?) async {
        guard let sid = extractStackID(maybeStack) else {
            DiagLog.log("[ACT] ensure WARN could not extract stackID from Stack")
            return
        }
        await refreshFromGroup(stackID: sid, excludeID: nil)
    }

    /// Keep this for callers that already have the ID and just want a minimal ensure.
    @MainActor
    static func startOrUpdateIfNeeded(forStackID stackID: String) async {
        await refreshFromGroup(stackID: stackID, excludeID: nil)
    }

    /// Called by pre-arm planning or opportunistically; not gated.
    @MainActor
    static func attemptStartNow(stackID: String, calendar: Calendar = .current) async {
        await refreshFromGroup(stackID: stackID, excludeID: nil)
    }

    // MARK: Core refresh (reads App Group → creates/updates LA)

    @MainActor
    private static func refreshFromGroup(stackID: String, excludeID: String?) async {
        // Local kill-switch or OS disabled → bail early.
        if LAFlags.deviceDisabled {
            DiagLog.log("[ACT] refresh.skip (device disabled) stack=\(stackID)")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            DiagLog.log("[ACT] refresh.skip (LA disabled by OS) stack=\(stackID)")
            return
        }

        let ids = LAUD.rStringArray(LA.storageKey(forStackID: stackID))
        let now = Date()

        // Existing activity for this stack (if any), else fall back to a bridge.
        let existingExact = Activity<AlarmActivityAttributes>.activities
            .first(where: { $0.attributes.stackID == stackID })
        let existing = existingExact ?? LAEnsure.findExisting(stackID: nil)

        // If nothing tracked at the moment, keep any existing LA rather than ending.
        if ids.isEmpty {
            if let a = existing {
                let lead = a.content.state.ends.timeIntervalSince(now)
                DiagLog.log(String(format: "[ACT] refresh.noTracked.keep stack=%@ lead=%.0fs", stackID, lead))
            } else {
                DiagLog.log("[ACT] refresh.noTracked stack=\(stackID) (no existing) → no-op")
            }
            return
        }

        // Build the best candidate (earliest future step for this stack)
        let firstEpoch = LAUD.rDouble(LA.firstTargetKey(forStackID: stackID))

        struct Candidate {
            var id: String
            var date: Date
            var stackName: String
            var stepTitle: String
            var allowSnooze: Bool
        }

        var best: Candidate?

        for s in ids {
            if let excludeID, s == excludeID { continue }
            guard let uuid = UUID(uuidString: s) else { continue }

            let stackName = LAUD.rString(LA.stackNameKey(for: uuid)) ?? "Alarm"
            let stepTitle = LAUD.rString(LA.stepTitleKey(for: uuid)) ?? "Step"
            let allow     = LAUD.rBool(LA.allowSnoozeKey(for: uuid), default: false)

            let effEpoch = LAUD.rDouble(LA.effTargetKey(for: uuid))
            let expEpoch = LAUD.rDouble(LA.expectedKey(for: uuid))
            let offAny   = LAUD.rDoubleAny(LA.offsetFromFirstKey(for: uuid))

            let date: Date? = {
                if effEpoch > 0 { return Date(timeIntervalSince1970: effEpoch) }
                if expEpoch > 0 { return Date(timeIntervalSince1970: expEpoch) }
                if firstEpoch > 0, let off = offAny { return Date(timeIntervalSince1970: firstEpoch + off) }
                return nil
            }()

            guard let d = date, d >= now.addingTimeInterval(-2) else { continue }

            if let b = best {
                if d < b.date {
                    best = Candidate(id: uuid.uuidString, date: d, stackName: stackName, stepTitle: stepTitle, allowSnooze: allow)
                }
            } else {
                best = Candidate(id: uuid.uuidString, date: d, stackName: stackName, stepTitle: stepTitle, allowSnooze: allow)
            }
        }

        // If we couldn't compute a future candidate, keep the current LA instead of ending it.
        guard let chosen = best else {
            if let a = existing {
                let lead = a.content.state.ends.timeIntervalSince(now)
                DiagLog.log(String(format: "[ACT] refresh.noFuture.keep stack=%@ lead=%.0fs", stackID, lead))
            } else {
                DiagLog.log("[ACT] refresh.noFuture stack=\(stackID) (no existing) → no-op")
            }
            return
        }

        // Optional: if it's very far out, end only if the existing LA belongs to THIS stack.
        let lead = chosen.date.timeIntervalSince(now)
        if lead > LA.nearWindow {
            if let a = existingExact {
                let st = a.content.state
                await a.end(
                    ActivityContent(state: st, staleDate: nil),
                    dismissalPolicy: .immediate
                )
                DiagLog.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → end")
            } else {
                DiagLog.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → keep bridge/none")
            }
            return
        }

        // ✅ Create early or update the single reusable activity.
        await LAEnsure.ensure(
            stackID: stackID,
            stackName: chosen.stackName,
            stepTitle: chosen.stepTitle,     // UI copy handled in the widget; pass raw step name here.
            ends: chosen.date,
            allowSnooze: chosen.allowSnooze,
            alarmID: chosen.id,
            theme: existing?.content.state.theme ?? ThemeMap.payload(for: "Default"),
            firedAt: nil
        )
    }

    // MARK: Helpers

    /// Extract a UUID/String ID from anything that looks like your `Stack` model.
    private static func extractStackID(_ any: Any?) -> String? {
        guard let any else { return nil }
        if let s = any as? String { return s }
        if let u = any as? UUID { return u.uuidString }

        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label else { continue }
            if label == "id" || label == "uuid" || label == "stackID" {
                if let s = child.value as? String { return s }
                if let u = child.value as? UUID { return u.uuidString }
            }
        }
        return nil
    }

    #if canImport(UIKit)
    @MainActor private static var isActive: Bool {
        UIApplication.shared.applicationState == .active
    }
    #else
    @MainActor private static var isActive: Bool { true }
    #endif
}

// MARK: - Local key helpers (same strings as in AlarmControlIntents, but renamed to avoid redeclaration)

private enum LA {
    static func storageKey(forStackID stackID: String) -> String { "alarmkit.ids.\(stackID)" }
    static func stackNameKey(for id: UUID) -> String { "ak.stackName.\(id.uuidString)" }
    static func stepTitleKey(for id: UUID) -> String { "ak.stepTitle.\(id.uuidString)" }
    static func allowSnoozeKey(for id: UUID) -> String { "ak.allowSnooze.\(id.uuidString)" }
    static func effTargetKey(for id: UUID) -> String { "ak.effTarget.\(id.uuidString)" }
    static func expectedKey(for id: UUID) -> String { "ak.expected.\(id.uuidString)" }
    static func offsetFromFirstKey(for id: UUID) -> String { "ak.offsetFromFirst.\(id.uuidString)" }
    static func firstTargetKey(forStackID id: String) -> String { "ak.firstTarget.\(id)" }

    static let nearWindow: TimeInterval = 2 * 60 * 60 // 2h window for initial visibility
}

// Unified read-only shim (Group → Standard)
private enum LAUD {
    static let group = UserDefaults(suiteName: "group.com.hodlsimulator.alarmstacks")

    static func rString(_ key: String) -> String? {
        if let v = group?.string(forKey: key) { return v }
        return UserDefaults.standard.string(forKey: key)
    }
    static func rStringArray(_ key: String) -> [String] {
        if let v = group?.stringArray(forKey: key) { return v }
        return UserDefaults.standard.stringArray(forKey: key) ?? []
    }
    static func rDouble(_ key: String) -> Double {
        if let v = group?.object(forKey: key) as? Double { return v }
        return (UserDefaults.standard.object(forKey: key) as? Double) ?? 0
    }
    static func rBool(_ key: String, default def: Bool = false) -> Bool {
        if let v = group?.object(forKey: key) as? Bool { return v }
        if let v = UserDefaults.standard.object(forKey: key) as? Bool { return v }
        return def
    }
    static func rDoubleAny(_ key: String) -> Double? {
        (group?.object(forKey: key) ?? UserDefaults.standard.object(forKey: key)) as? Double
    }
}
