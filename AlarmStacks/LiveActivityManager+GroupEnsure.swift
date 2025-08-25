//
//  LiveActivityManager+GroupEnsure.swift
//  AlarmStacks
//
//  Restores the legacy `ensureFromAppGroup` entrypoints that LAGroupWriter calls.
//  - These are async (so callers can `await` them).
//  - They delegate to LiveActivityManager.shared.sync(...).
//  - Local helper functions are included so we don't depend on `private` symbols.
//

import Foundation

@MainActor
extension LiveActivityManager {

    // MARK: - Public shims (async)

    /// Primary shim used by LAGroupWriter when it updates app-group keys.
    /// Triggers a sync for the provided stackID.
    static func ensureFromAppGroup(stackID: String, reason: String = "group.write") async {
        await LiveActivityManager.shared.sync(stackID: stackID, reason: reason)
    }

    /// Unlabeled convenience (covers older call sites).
    static func ensureFromAppGroup(_ stackID: String) async {
        await LiveActivityManager.shared.sync(stackID: stackID, reason: "group.write")
    }

    /// Accepts a generic stack object and tries to extract its ID.
    static func ensureFromAppGroup(stack: Any, reason: String = "group.write") async {
        if let sid = extractStackIDStringCompat(from: stack) {
            await LiveActivityManager.shared.sync(stackID: sid, reason: reason)
        } else {
            MiniDiag.log("[ACT] ensureFromAppGroup WARN could not extract stackID from \(type(of: stack))")
        }
    }

    /// Allows callers that only know an alarmID to trigger a sync for its stack.
    static func ensureFromAppGroup(alarmID: String, reason: String = "group.write.alarm") async {
        if let sid = resolveStackIDFromAlarmIDCompat(alarmID) {
            await LiveActivityManager.shared.sync(stackID: sid, reason: reason)
        } else {
            MiniDiag.log("[ACT] ensureFromAppGroup WARN no stackID mapping for alarm \(alarmID)")
        }
    }

    // MARK: - Local helpers (do not rely on private symbols from other files)

    /// App Group used by AlarmStacks.
    private static let groupSuiteName = "group.com.hodlsimulator.alarmstacks"

    /// Read a string from the app group first, then fall back to standard defaults.
    private static func rStringCompat(_ key: String) -> String? {
        if let v = UserDefaults(suiteName: groupSuiteName)?.string(forKey: key) { return v }
        return UserDefaults.standard.string(forKey: key)
    }

    /// Attempt to pull a stackID string out of any object (e.g., your `Stack` model).
    /// Mirrors the logic used in the main manager, but kept local so this file compiles independently.
    private static func extractStackIDStringCompat(from any: Any) -> String? {
        if let s = any as? String { return s }
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label?.lowercased() else { continue }
            if label == "id" || label == "stackid" || label == "identifier" {
                if let s = child.value as? String { return s }
                if let u = child.value as? UUID { return u.uuidString }
            }
            if label == "uuid" || label == "uuidstring" {
                if let u = child.value as? UUID { return u.uuidString }
                if let s = child.value as? String { return s }
            }
        }
        return nil
    }

    /// Map an alarm UUID string back to its stackID using the stored key:
    ///   "ak.stackID.<alarmUUID>"
    private static func resolveStackIDFromAlarmIDCompat(_ alarmID: String) -> String? {
        guard let u = UUID(uuidString: alarmID) else { return nil }
        let key = "ak.stackID.\(u.uuidString)"
        return rStringCompat(key)
    }
}
