//
//  PreferredAppearance.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI

// MARK: - Appearance mode

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Never returns `nil`. For `.system` we forward the **current base** scheme so updates
    /// propagate correctly while a sheet is open.
    func resolvedColorScheme(using base: ColorScheme) -> ColorScheme {
        switch self {
        case .system: return base
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Theme tint (shared with ThemePickerView choices)

private func tintColor(for name: String) -> Color {
    switch name {
    case "Default":  return Color(red: 0.04, green: 0.52, blue: 1.00) // iOS blue
    case "Forest":   return Color(red: 0.16, green: 0.62, blue: 0.39)
    case "Coral":    return Color(red: 0.98, green: 0.45, blue: 0.35)

    case "Indigo":   return Color(red: 0.35, green: 0.37, blue: 0.80)
    case "Grape":    return Color(red: 0.56, green: 0.27, blue: 0.68)
    case "Mint":     return Color(red: 0.22, green: 0.77, blue: 0.58)
    case "Flamingo": return Color(red: 1.00, green: 0.35, blue: 0.62)
    case "Slate":    return Color(red: 0.36, green: 0.42, blue: 0.49)
    case "Midnight": return Color(red: 0.10, green: 0.14, blue: 0.28)

    default:         return Color(red: 0.04, green: 0.52, blue: 1.00)
    }
}

// MARK: - Global appearance modifier
//
// Fixes: When switching from Light → System (device dark) while a sheet is open,
// the sheet now flips immediately to dark. We never pass `nil` into preferredColorScheme.
// Instead we **explicitly** set the environment colorScheme to either the user's choice
// or the current base scheme for `.system`. Tint is centralized here so every presentation
// scope (including sheets) picks it up consistently.

struct PreferredAppearance: ViewModifier {
    @Environment(\.colorScheme) private var baseScheme

    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")     private var themeName: String = "Default"

    func body(content: Content) -> some View {
        let selected = AppearanceMode(rawValue: mode) ?? .system
        let effective = selected.resolvedColorScheme(using: baseScheme)

        // Use environment(\.colorScheme, …) so updates propagate reliably in sheets.
        content
            .environment(\.colorScheme, effective)
            .tint(tintColor(for: themeName))
    }
}

extension View {
    /// Apply the app’s unified appearance (color scheme + tint).
    func preferredAppearance() -> some View { modifier(PreferredAppearance()) }
}
