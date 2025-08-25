//
//  LAGroupWriter.swift
//  AlarmStacks
//
//  Created by . . on 8/24/25.
//
//  Writes the minimal App Group keys that LiveActivityManager.refreshFromGroup()
//  expects to find, and offers a tiny API you can call from AlarmKitScheduler.
//

import Foundation

enum LAGroupWriter {

    // MARK: - Public API

    /// Record (or update) one planned step in the App Group so the LA refresher can see it.
    ///
    /// Call this immediately after you schedule a step.
    ///
    /// - Parameters:
    ///   - stackID: stable ID for the stack (same value you pass to AlarmActivityAttributes)
    ///   - alarmID: the UUID of the step/occurrence (matches your AK logs)
    ///   - stackName: display name (e.g. “Sunday 2”)
    ///   - stepTitle: display title (e.g. “Start”, “Step 2”)
    ///   - effTarget: effective fire time (Date you log as `effTarget`)
    ///   - allowSnooze: whether snooze is allowed for this step
    ///   - firstTarget: earliest fire time **for this stack** in the chain (optional but helps offsets)
    ///   - expected: a nominal/expected time if you track both (optional)
    static func recordStep(
        stackID: String,
        alarmID: UUID,
        stackName: String,
        stepTitle: String,
        effTarget: Date,
        allowSnooze: Bool,
        firstTarget: Date? = nil,
        expected: Date? = nil
    ) {
        let g = UD.group
        let idStr = alarmID.uuidString

        // 1) Maintain the list of alarm IDs for this stack
        var ids = readIDs(forStackID: stackID)
        if ids.contains(idStr) == false {
            ids.append(idStr)
            g?.set(ids, forKey: Keys.storageKey(forStackID: stackID))
        }

        // 2) Per-alarm metadata (these exact keys are what LiveActivityManager reads)
        g?.set(stackName,                       forKey: Keys.stackNameKey(for: alarmID))
        g?.set(stepTitle,                       forKey: Keys.stepTitleKey(for: alarmID))
        g?.set(allowSnooze,                     forKey: Keys.allowSnoozeKey(for: alarmID))
        g?.set(effTarget.timeIntervalSince1970, forKey: Keys.effTargetKey(for: alarmID))

        if let expected {
            g?.set(expected.timeIntervalSince1970, forKey: Keys.expectedKey(for: alarmID))
        }

        // 3) (Optional) First target + offset — useful when you only have relative offsets
        if let first = firstTarget {
            let firstEpoch = first.timeIntervalSince1970
            let existing = g?.object(forKey: Keys.firstTargetKey(forStackID: stackID)) as? Double ?? 0
            if existing <= 0 || firstEpoch < existing {
                g?.set(firstEpoch, forKey: Keys.firstTargetKey(forStackID: stackID))
            }
            let offset = effTarget.timeIntervalSince(first)
            g?.set(offset, forKey: Keys.offsetFromFirstKey(for: alarmID))
        }

        // Keep Standard in sync as a fallback (the reader checks both)
        syncStandardMirror(stackID: stackID, alarmID: alarmID)

        // 4) Nudge logic:
        //    Do NOT call ensureFromAppGroup for far-future steps — that path may
        //    immediately end a freshly-started LA (you can see this in logs as
        //    "refresh.skip ... far-future ... → end").
        //    Prearm will handle far-future reliably; only nudge when close.
        let lead = effTarget.timeIntervalSinceNow
        if lead <= 90 { // within ~1½ minutes, safe to nudge refresher
            Task { @MainActor in
                await LiveActivityManager.ensureFromAppGroup(stackID: stackID)
            }
        } else {
            // Far in the future: do nothing here. The prearm pipeline you trigger elsewhere
            // (recordPrearmContext + prearmIfNeeded) will create/update at the right times
            // without fighting the refresher's far-future policy.
        }
    }

    /// Remove a planned step (e.g., when cancelled or after it fires).
    static func removeStep(stackID: String, alarmID: UUID) {
        let g = UD.group
        let idStr = alarmID.uuidString

        var ids = readIDs(forStackID: stackID)
        if let i = ids.firstIndex(of: idStr) {
            ids.remove(at: i)
            g?.set(ids, forKey: Keys.storageKey(forStackID: stackID))
        }

        // Best-effort cleanup of per-alarm keys
        g?.removeObject(forKey: Keys.stackNameKey(for: alarmID))
        g?.removeObject(forKey: Keys.stepTitleKey(for: alarmID))
        g?.removeObject(forKey: Keys.allowSnoozeKey(for: alarmID))
        g?.removeObject(forKey: Keys.effTargetKey(for: alarmID))
        g?.removeObject(forKey: Keys.expectedKey(for: alarmID))
        g?.removeObject(forKey: Keys.offsetFromFirstKey(for: alarmID))
    }

    // MARK: - Internals

    private enum UD {
        static let group = UserDefaults(suiteName: "group.com.hodlsimulator.alarmstacks")
        static let standard = UserDefaults.standard
    }

    /// Keys MUST match what `LiveActivityManager+Start.swift` reads.
    private enum Keys {
        static func storageKey(forStackID stackID: String) -> String { "alarmkit.ids.\(stackID)" }
        static func stackNameKey(for id: UUID) -> String { "ak.stackName.\(id.uuidString)" }
        static func stepTitleKey(for id: UUID) -> String { "ak.stepTitle.\(id.uuidString)" }
        static func allowSnoozeKey(for id: UUID) -> String { "ak.allowSnooze.\(id.uuidString)" }
        static func effTargetKey(for id: UUID) -> String { "ak.effTarget.\(id.uuidString)" }
        static func expectedKey(for id: UUID) -> String { "ak.expected.\(id.uuidString)" }
        static func offsetFromFirstKey(for id: UUID) -> String { "ak.offsetFromFirst.\(id.uuidString)" }
        static func firstTargetKey(forStackID id: String) -> String { "ak.firstTarget.\(id)" }
    }

    private static func readIDs(forStackID stackID: String) -> [String] {
        if let v = UD.group?.stringArray(forKey: Keys.storageKey(forStackID: stackID)) { return v }
        return UD.standard.stringArray(forKey: Keys.storageKey(forStackID: stackID)) ?? []
    }

    /// Mirror group values to Standard defaults as a fallback (the reader checks both).
    private static func syncStandardMirror(stackID: String, alarmID: UUID) {
        guard let g = UD.group else { return }
        let s = UD.standard

        s.set(readIDs(forStackID: stackID), forKey: Keys.storageKey(forStackID: stackID))

        for key in [
            Keys.stackNameKey(for: alarmID),
            Keys.stepTitleKey(for: alarmID),
            Keys.allowSnoozeKey(for: alarmID),
            Keys.effTargetKey(for: alarmID),
            Keys.expectedKey(for: alarmID),
            Keys.offsetFromFirstKey(for: alarmID),
            Keys.firstTargetKey(forStackID: stackID)
        ] {
            if let v = g.object(forKey: key) {
                s.set(v, forKey: key)
            }
        }
    }
}
