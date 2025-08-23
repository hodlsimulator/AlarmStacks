//
//  AppGroups.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import Foundation

/// Your shared app group used for cross-process UserDefaults.
/// If your identifier is different, change it here in one place.
enum AppGroups {
    /// Canonical App Group identifier.
    static let suite = "group.com.hodlsimulator.alarmstacks"

    /// Backward-compat alias for older call sites (e.g. widget code).
    static let main = suite

    /// Convenience accessor for the group defaults (nil if misconfigured).
    static let defaults: UserDefaults? = UserDefaults(suiteName: suite)
}
    