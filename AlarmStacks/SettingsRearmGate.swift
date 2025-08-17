//
//  SettingsRearmGate.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation

/// A tiny flag that lets us re-arm alarms ONLY after the user tapped "Open Settings"
/// from our explainer. This avoids stomping live timers on every foreground transition.
enum SettingsRearmGate {
    private static let key = "needsRearmAfterSettings"

    static func mark() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Returns true if we should re-arm now, and clears the flag.
    static func consume() -> Bool {
        let should = UserDefaults.standard.bool(forKey: key)
        if should {
            UserDefaults.standard.set(false, forKey: key)
        }
        return should
    }
}
