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

    /// Call this from the scheduler *while the app is foreground* (right after you persist App Group keys).
    @MainActor
    static func ensureFromAppGroup(stackID: String) async {
        guard isActive else {
            MiniDiag.log("[ACT] ensure.skip (not active) stack=\(stackID)")
            return
        }
        await refreshFromGroup(stackID: stackID, excludeID: nil)
    }

    /// Convenience: use if your call sites pass a `Stack` (or anything) instead of a String.
    @MainActor
    static func ensureFromStack(_ maybeStack: Any?) async {
        guard isActive else {
            MiniDiag.log("[ACT] start.skip (not active)")
            return
        }
        guard let sid = extractStackID(maybeStack) else {
            MiniDiag.log("[ACT] start WARN could not extract stackID from Stack")
            return
        }
        await refreshFromGroup(stackID: sid, excludeID: nil)
    }

    /// Keep this for callers that already have the ID and just want a minimal ensure.
    @MainActor
    static func startOrUpdateIfNeeded(forStackID stackID: String) async {
        guard isActive else {
            MiniDiag.log("[ACT] ensure.skip (not active) stack=\(stackID)")
            return
        }
        await refreshFromGroup(stackID: stackID, excludeID: nil)
    }

    // MARK: Core refresh (reads App Group → creates/updates/ends LA)

    @MainActor
    private static func refreshFromGroup(stackID: String, excludeID: String?) async {
        let ids = LAUD.rStringArray(LA.storageKey(forStackID: stackID))
        let now = Date()

        // Existing activity for this stack (if any)
        let existing = Activity<AlarmActivityAttributes>.activities
            .first(where: { $0.attributes.stackID == stackID })

        guard ids.isEmpty == false else {
            if let a = existing {
                let st = a.content.state
                await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                MiniDiag.log("[ACT] refresh.end stack=\(stackID) no-tracked → end")
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

        // Nothing future → end if present
        guard let chosen = best else {
            if let a = existing {
                let st = a.content.state
                await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                MiniDiag.log("[ACT] refresh.end stack=\(stackID) no-future → end")
            }
            return
        }

        // Far-future (avoid showing “in 23h” on first lock)
        let lead = chosen.date.timeIntervalSince(now)
        if lead > LA.nearWindow {
            if let a = existing {
                let st = a.content.state
                await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .immediate)
                MiniDiag.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → end")
            } else {
                MiniDiag.log("[ACT] refresh.skip stack=\(stackID) far-future lead=\(Int(lead))s → no-op")
            }
            return
        }

        // Build state (preserve current theme if we have one)
        let currentTheme = existing?.content.state.theme
        var newState = AlarmActivityAttributes.ContentState(
            stackName: chosen.stackName,
            stepTitle: chosen.stepTitle,
            ends: chosen.date,
            allowSnooze: chosen.allowSnooze,
            alarmID: chosen.id,
            firedAt: nil
        )
        if let theme = currentTheme { newState.theme = theme }

        if let a = existing {
            // Skip churn if identical
            let st = a.content.state
            if st.stackName == newState.stackName &&
                st.stepTitle == newState.stepTitle &&
                st.ends == newState.ends &&
                st.allowSnooze == newState.allowSnooze &&
                st.firedAt == nil &&
                st.alarmID == newState.alarmID {
                return
            }
            await a.update(ActivityContent(state: newState, staleDate: nil))
            MiniDiag.log("[ACT] refresh.update stack=\(stackID) step=\(newState.stepTitle) ends=\(newState.ends) id=\(newState.alarmID)")
        } else {
            do {
                _ = try Activity.request(
                    attributes: AlarmActivityAttributes(stackID: stackID),
                    content: ActivityContent(state: newState, staleDate: nil),
                    pushType: nil
                )
                MiniDiag.log("[ACT] refresh.start stack=\(stackID) step=\(newState.stepTitle) ends=\(newState.ends) id=\(newState.alarmID)")
            } catch {
                MiniDiag.log("[ACT] refresh request failed stack=\(stackID) error=\(error)")
            }
        }
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
