//
//  AlarmKitSnoozeMap.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

#if canImport(AlarmKit)

import Foundation

/// Persists a tiny mapping from AlarmKit alarm UUID -> per-step snooze minutes.
/// Used by the in-app overlay so it can label Snooze with the right duration
/// when AlarmKit's alert UI doesn't show.
///
/// Keys are UUID strings; values are Int minutes.
enum AlarmKitSnoozeMap {
    private static let key = "alarmkit.snoozeMinutesByID.v1"

    static func set(minutes: Int, for id: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        dict[id.uuidString] = minutes
        UserDefaults.standard.set(dict, forKey: key)
    }

    static func minutes(for id: UUID) -> Int? {
        let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        return dict[id.uuidString]
    }

    static func remove(for id: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        dict[id.uuidString] = nil
        UserDefaults.standard.set(dict, forKey: key)
    }

    static func removeAll(for ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        for id in ids { dict[id.uuidString] = nil }
        UserDefaults.standard.set(dict, forKey: key)
    }
}

#endif
