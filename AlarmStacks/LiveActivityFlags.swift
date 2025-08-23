//
//  LiveActivityFlags.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import Foundation

/// Simple per-device switch to temporarily disable all Live Activity starts.
enum LAFlags {
    private static let disableKey = "debug.disableLA"

    static var deviceDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: disableKey) }
        set { UserDefaults.standard.set(newValue, forKey: disableKey) }
    }
}
