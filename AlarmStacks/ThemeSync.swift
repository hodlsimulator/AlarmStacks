//
//  ThemeSync.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI

/// Mirrors the in-app theme selection into the shared app-group defaults
/// so the widget/Live Activity can read it immediately.
struct ThemeSync: ViewModifier {
    @AppStorage("themeName") private var themeName: String = "Default"

    func body(content: Content) -> some View {
        content
            .onAppear(perform: write)
            // iOS 17+: use the two-parameter onChange closure to silence deprecation.
            .onChange(of: themeName) { _, _ in
                write()
            }
    }

    private func write() {
        let d = UserDefaults(suiteName: AppGroups.main)
        if d?.string(forKey: "themeName") != themeName {
            d?.set(themeName, forKey: "themeName")
        }
        // Ensure any existing Live Activities re-tint immediately.
        Task { await LiveActivityManager.resyncThemeForActiveActivities() }
    }
}

extension View {
    /// Call this once at the app root so the widget can see the current theme.
    func syncThemeToAppGroup() -> some View { modifier(ThemeSync()) }
}
