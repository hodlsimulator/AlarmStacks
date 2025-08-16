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

    // MARK: - Defaults
    @Published var defaultAllowSnooze: Bool {
        didSet { UserDefaults.standard.set(defaultAllowSnooze, forKey: Keys.defaultAllowSnooze) }
    }
    @Published var defaultSnoozeMinutes: Int {
        didSet { UserDefaults.standard.set(defaultSnoozeMinutes, forKey: Keys.defaultSnoozeMinutes) }
    }

    private struct Keys {
        static let defaultAllowSnooze   = "settings.defaultAllowSnooze"
        static let defaultSnoozeMinutes = "settings.defaultSnoozeMinutes"
    }

    private init() {
        let d = UserDefaults.standard
        defaultAllowSnooze   = d.object(forKey: Keys.defaultAllowSnooze) as? Bool ?? true
        defaultSnoozeMinutes = d.object(forKey: Keys.defaultSnoozeMinutes) as? Int  ?? 9
    }
}
