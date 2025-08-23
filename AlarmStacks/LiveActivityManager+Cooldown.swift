//
//  LiveActivityManager+Cooldown.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation

extension LiveActivityManager {
    private static let cooldownKey = "la.cooldown.until"

    /// Are we currently in an ActivityKit "cool-down" period after an error?
    static var isInCooldown: Bool {
        (UserDefaults.standard.object(forKey: cooldownKey) as? Date).map { $0 > Date() } ?? false
    }

    /// Start a cool-down window. During this, pre-arm attempts are skipped.
    static func beginCooldown(seconds: TimeInterval, reason: String) {
        let until = Date().addingTimeInterval(seconds)
        UserDefaults.standard.set(until, forKey: cooldownKey)
        DiagLog.log("[ACT] cooldown.begin reason=\(reason) until=\(DiagLog.f(until)) (~\(Int(seconds))s)")
    }

    /// Clear any cool-down (rare).
    static func clearCooldown() {
        UserDefaults.standard.removeObject(forKey: cooldownKey)
        DiagLog.log("[ACT] cooldown.clear")
    }
}
