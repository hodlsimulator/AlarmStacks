//
//  LiveActivityTheme.swift
//  AlarmStacksWidget
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import WidgetKit

// Accent-only theme for Live Activity surfaces.
struct LiveActivityTheme {
    let accent: Color

    static func current(_ scheme: ColorScheme) -> LiveActivityTheme {
        let name = UserDefaults(suiteName: AppGroups.main)?
            .string(forKey: "themeName") ?? "Default"
        return .init(accent: accentColor(for: name))
    }

    private static func accentColor(for name: String) -> Color {
        switch name {
        case "Forest":   return Color(red: 0.16, green: 0.62, blue: 0.39)
        case "Coral":    return Color(red: 0.98, green: 0.45, blue: 0.35)
        case "Indigo":   return Color(red: 0.35, green: 0.37, blue: 0.80)
        case "Grape":    return Color(red: 0.56, green: 0.27, blue: 0.68)
        case "Mint":     return Color(red: 0.22, green: 0.77, blue: 0.58)
        case "Flamingo": return Color(red: 1.00, green: 0.35, blue: 0.62)
        case "Slate":    return Color(red: 0.36, green: 0.42, blue: 0.49)
        case "Midnight": return Color(red: 0.10, green: 0.14, blue: 0.28)
        default:         return Color(red: 0.04, green: 0.52, blue: 1.00) // iOS blue
        }
    }
}

// Modifier applies only the accent tint (no background tinting).
private struct LiveActivityAccentModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let t = LiveActivityTheme.current(scheme)
        return content.tint(t.accent)
    }
}

extension View {
    /// Apply to ActivityConfiguration views (lock screen + island).
    func applyLiveActivityTheme() -> some View { modifier(LiveActivityAccentModifier()) }
}
