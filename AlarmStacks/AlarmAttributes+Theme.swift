//
//  AlarmAttributes+Theme.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

#if canImport(AlarmKit)

import SwiftUI
import AlarmKit

/// Resolve the current app accent from @AppStorage / App Group.
public enum ThemeTintResolver {
    public static func currentAccent() -> Color {
        let std = UserDefaults.standard.string(forKey: "themeName")
        let grp = UserDefaults(suiteName: AppGroups.main)?.string(forKey: "themeName")
        let name = std ?? grp ?? "Default"
        return ThemeMap.accent(for: name)
    }
}

public extension AlarmAttributes {
    /// Build themed attributes for any metadata type.
    static func themed<M>(presentation: AlarmPresentation, as _: M.Type) -> AlarmAttributes<M> where M: AlarmMetadata {
        AlarmAttributes<M>(
            presentation: presentation,
            tintColor: ThemeTintResolver.currentAccent()
        )
    }

    /// Convenience taking an Alert directly.
    static func themed<M>(alert: AlarmPresentation.Alert, as _: M.Type) -> AlarmAttributes<M> where M: AlarmMetadata {
        themed(presentation: AlarmPresentation(alert: alert), as: M.self)
    }
}

#endif
