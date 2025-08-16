//
//  Settings.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import Combine

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    // MARK: - Defaults for new steps
    @Published var defaultAllowSnooze: Bool {
        didSet { UserDefaults.standard.set(defaultAllowSnooze, forKey: Keys.defaultAllowSnooze) }
    }
    @Published var defaultSnoozeMinutes: Int {
        didSet { UserDefaults.standard.set(defaultSnoozeMinutes, forKey: Keys.defaultSnoozeMinutes) }
    }

    // MARK: - Alarm behaviour (UN boost while unlocked)
    /// Mirror an unlocked AlarmKit fire with Time-Sensitive UN banners + sound.
    @Published var boostUnlockedWithUN: Bool {
        didSet { UserDefaults.standard.set(boostUnlockedWithUN, forKey: Keys.boostUnlockedWithUN) }
    }
    /// Number of UN “boost” pings (≥ 1).
    @Published var unlockedBoostCount: Int {
        didSet { UserDefaults.standard.set(max(1, unlockedBoostCount), forKey: Keys.unlockedBoostCount) }
    }
    /// Seconds between UN boost pings (≥ 1).
    @Published var unlockedBoostSpacingSeconds: Int {
        didSet { UserDefaults.standard.set(max(1, unlockedBoostSpacingSeconds), forKey: Keys.unlockedBoostSpacingSeconds) }
    }

    private struct Keys {
        static let defaultAllowSnooze           = "settings.defaultAllowSnooze"
        static let defaultSnoozeMinutes         = "settings.defaultSnoozeMinutes"
        static let boostUnlockedWithUN          = "settings.boostUnlockedWithUN"
        static let unlockedBoostCount           = "settings.unlockedBoostCount"
        static let unlockedBoostSpacingSeconds  = "settings.unlockedBoostSpacingSeconds"
    }

    private init() {
        let d = UserDefaults.standard
        // Step defaults
        defaultAllowSnooze   = d.object(forKey: Keys.defaultAllowSnooze) as? Bool ?? true
        defaultSnoozeMinutes = d.object(forKey: Keys.defaultSnoozeMinutes) as? Int  ?? 9
        // Alarm behaviour defaults
        boostUnlockedWithUN         = d.object(forKey: Keys.boostUnlockedWithUN) as? Bool ?? true
        unlockedBoostCount          = max(1, (d.object(forKey: Keys.unlockedBoostCount) as? Int) ?? 3)
        unlockedBoostSpacingSeconds = max(1, (d.object(forKey: Keys.unlockedBoostSpacingSeconds) as? Int) ?? 7)
    }
}
