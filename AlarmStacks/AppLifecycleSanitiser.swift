//
//  AppLifecycleSanitiser.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//

import Foundation

@MainActor
enum AppLifecycleSanitiser {
    static func start() {
        // Force ACTIVE mode immediately in all builds.
        AlarmSanitiser.shared.mode = .active

        // If/when you expose a concrete canceller, set it here:
        // AlarmSanitiser.shared.canceller = { id in /* cancel in your scheduler */ }

        // Cold start pass.
        AlarmSanitiser.shared.run(reason: .launch)
    }

    static func foregroundPass() {
        AlarmSanitiser.shared.run(reason: .foreground)
    }
}
