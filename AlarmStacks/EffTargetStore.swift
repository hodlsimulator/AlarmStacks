//
//  EffTargetStore.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//
//  Purpose:
//  - Ensure we always persist the effective target timestamp per AlarmKit ID
//    BEFORE returning from any schedule call (including snooze).
//  - Keep it main-thread safe to silence concurrency warnings.
//

import Foundation

enum EffTargetStore {
    private static let keyPrefix = "ak.effTarget." // ak.effTarget.<uuid>

    /// Persist *before* scheduling returns.
    @MainActor
    static func set(_ date: Date, forAlarmID alarmID: String) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: keyPrefix + alarmID)
        print("AK persist effTarget id=\(alarmID) t=\(Int(date.timeIntervalSince1970))")
    }

    static func get(_ alarmID: String) -> Date? {
        let key = keyPrefix + alarmID
        guard let ts = UserDefaults.standard.object(forKey: key) as? Double else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    @MainActor
    static func clear(_ alarmID: String) {
        UserDefaults.standard.removeObject(forKey: keyPrefix + alarmID)
    }
}
