//
//  LiveActivityTheme.swift
//  AlarmStacksWidget
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import WidgetKit

// MARK: - iOS 17 compatibility helper (activity background tint)
private struct ActivityBackgroundTintCompat: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.activityBackgroundTint(color)
        } else {
            content
        }
    }
}

private extension View {
    func activityBackgroundTintCompat(_ color: Color) -> some View {
        modifier(ActivityBackgroundTintCompat(color: color))
    }
}

// MARK: - Theme mapping used by the Live Activity (banner / island / lock screen)

struct LiveActivityTheme {
    let accent: Color
    let background: Color

    static func current(_ scheme: ColorScheme) -> LiveActivityTheme {
        let name = UserDefaults(suiteName: AppGroups.main)?
            .string(forKey: "themeName") ?? "Default"
        return .init(
            accent: accentColor(for: name),
            background: backgroundColor(for: name, scheme: scheme)
        )
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

    private static func backgroundColor(for name: String, scheme: ColorScheme) -> Color {
        switch (name, scheme) {
        case ("Default", .light):  return Color(red: 1.00, green: 0.96, blue: 0.92)
        case ("Default", .dark):   return Color(red: 0.26, green: 0.22, blue: 0.18)
        case ("Forest", .light):   return Color(red: 0.99, green: 0.95, blue: 0.97)
        case ("Forest", .dark):    return Color(red: 0.21, green: 0.18, blue: 0.22)
        case ("Coral", .light):    return Color(red: 0.92, green: 0.98, blue: 0.97)
        case ("Coral", .dark):     return Color(red: 0.15, green: 0.20, blue: 0.20)
        case ("Indigo", .light):   return Color(red: 1.00, green: 0.97, blue: 0.90)
        case ("Indigo", .dark):    return Color(red: 0.26, green: 0.23, blue: 0.18)
        case ("Grape", .light):    return Color(red: 0.94, green: 0.99, blue: 0.96)
        case ("Grape", .dark):     return Color(red: 0.16, green: 0.22, blue: 0.19)
        case ("Mint", .light):     return Color(red: 0.96, green: 0.95, blue: 1.00)
        case ("Mint", .dark):      return Color(red: 0.20, green: 0.20, blue: 0.27)
        case ("Flamingo", .light): return Color(red: 0.93, green: 0.99, blue: 1.00)
        case ("Flamingo", .dark):  return Color(red: 0.18, green: 0.22, blue: 0.24)
        case ("Slate", .light):    return Color(red: 0.95, green: 0.97, blue: 1.00)
        case ("Slate", .dark):     return Color(red: 0.15, green: 0.17, blue: 0.21)
        case ("Midnight", .light): return Color(red: 1.00, green: 0.96, blue: 0.90)
        case ("Midnight", .dark):  return Color(red: 0.24, green: 0.20, blue: 0.15)
        default:
            return scheme == .dark
            ? Color(red: 0.20, green: 0.20, blue: 0.20)
            : Color(red: 0.97, green: 0.97, blue: 0.97)
        }
    }
}

// MARK: - Single call you add to your Activity views

private struct LiveActivityTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let t = LiveActivityTheme.current(scheme)
        return content
            .tint(t.accent)                         // controls, glyphs
            .activityBackgroundTintCompat(t.background)  // banner/lock bg
    }
}

extension View {
    /// Apply this to your ActivityConfiguration views (lock screen + island).
    func applyLiveActivityTheme() -> some View { modifier(LiveActivityTintModifier()) }
}
