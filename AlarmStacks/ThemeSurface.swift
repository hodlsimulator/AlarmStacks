//
//  ThemeSurface.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI

/// Pastel, low-saturation background that adapts to the selected theme and scheme.
/// Use `.themedSurface()` on Lists/Forms, and also place `ThemeSurfaceBackground()`
/// as a `.background(...)` on the root NavigationStack to colour the area behind
/// large titles and the safe areas.
struct ThemeSurfaceBackground: View {
    @AppStorage("themeName") private var themeName: String = "Default"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = palette[themeName, default: palette["Default"]!]

        // System base for readability, then we lay a visible "wash" and soft gradients.
        let systemBase = scheme == .dark ? Color.black : Color(.systemGroupedBackground)
        let wash       = scheme == .dark ? p.darkWash    : p.lightWash
        let top        = scheme == .dark ? p.darkTop     : p.lightTop
        let bottom     = scheme == .dark ? p.darkBottom  : p.lightBottom

        ZStack {
            systemBase

            // Stronger wash so Light mode is visibly coloured.
            // Tuned to stay tasteful with content contrast.
            wash.opacity(scheme == .dark ? 0.12 : 0.26)

            // Subtle directionality
            LinearGradient(colors: [top.opacity(scheme == .dark ? 0.12 : 0.18), .clear],
                           startPoint: .top, endPoint: .center)

            RadialGradient(colors: [bottom.opacity(scheme == .dark ? 0.16 : 0.22), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 820)
        }
        .ignoresSafeArea()
    }

    // MARK: - Palette

    private struct Trio {
        let lightWash: Color, lightTop: Color, lightBottom: Color
        let darkWash: Color,  darkTop:  Color, darkBottom:  Color
    }

    /// Complementary/analogous pastels per theme.
    /// `wash` is the uniform tint; `top/bottom` add gentle depth.
    private let palette: [String: Trio] = [
        // Blue → warm peach/orange
        "Default":  Trio(
            lightWash:  Color(red: 1.00, green: 0.96, blue: 0.92),
            lightTop:   Color(red: 1.00, green: 0.93, blue: 0.86),
            lightBottom:Color(red: 1.00, green: 0.88, blue: 0.72),
            darkWash:   Color(red: 0.26, green: 0.22, blue: 0.18),
            darkTop:    Color(red: 1.00, green: 0.90, blue: 0.80),
            darkBottom: Color(red: 1.00, green: 0.82, blue: 0.62)
        ),

        // Green → pink/magenta
        "Forest":   Trio(
            lightWash:  Color(red: 0.99, green: 0.95, blue: 0.97),
            lightTop:   Color(red: 1.00, green: 0.94, blue: 0.97),
            lightBottom:Color(red: 1.00, green: 0.88, blue: 0.95),
            darkWash:   Color(red: 0.21, green: 0.18, blue: 0.22),
            darkTop:    Color(red: 1.00, green: 0.88, blue: 0.95),
            darkBottom: Color(red: 1.00, green: 0.78, blue: 0.90)
        ),

        // Coral → teal
        "Coral":    Trio(
            lightWash:  Color(red: 0.92, green: 0.98, blue: 0.97),
            lightTop:   Color(red: 0.96, green: 0.99, blue: 0.98),
            lightBottom:Color(red: 0.86, green: 0.97, blue: 0.93),
            darkWash:   Color(red: 0.15, green: 0.20, blue: 0.20),
            darkTop:    Color(red: 0.86, green: 0.96, blue: 0.94),
            darkBottom: Color(red: 0.72, green: 0.90, blue: 0.86)
        ),

        // Indigo → amber
        "Indigo":   Trio(
            lightWash:  Color(red: 1.00, green: 0.97, blue: 0.90),
            lightTop:   Color(red: 1.00, green: 0.96, blue: 0.88),
            lightBottom:Color(red: 1.00, green: 0.90, blue: 0.74),
            darkWash:   Color(red: 0.26, green: 0.23, blue: 0.18),
            darkTop:    Color(red: 1.00, green: 0.93, blue: 0.78),
            darkBottom: Color(red: 1.00, green: 0.86, blue: 0.62)
        ),

        // Grape → mint/lime
        "Grape":    Trio(
            lightWash:  Color(red: 0.94, green: 0.99, blue: 0.96),
            lightTop:   Color(red: 0.95, green: 1.00, blue: 0.97),
            lightBottom:Color(red: 0.88, green: 0.98, blue: 0.92),
            darkWash:   Color(red: 0.16, green: 0.22, blue: 0.19),
            darkTop:    Color(red: 0.88, green: 0.97, blue: 0.90),
            darkBottom: Color(red: 0.80, green: 0.94, blue: 0.84)
        ),

        // Mint → lavender
        "Mint":     Trio(
            lightWash:  Color(red: 0.96, green: 0.95, blue: 1.00),
            lightTop:   Color(red: 0.96, green: 0.96, blue: 1.00),
            lightBottom:Color(red: 0.91, green: 0.90, blue: 1.00),
            darkWash:   Color(red: 0.20, green: 0.20, blue: 0.27),
            darkTop:    Color(red: 0.93, green: 0.90, blue: 0.99),
            darkBottom: Color(red: 0.86, green: 0.82, blue: 0.98)
        ),

        // Pink → teal
        "Flamingo": Trio(
            lightWash:  Color(red: 0.93, green: 0.99, blue: 1.00),
            lightTop:   Color(red: 0.94, green: 1.00, blue: 1.00),
            lightBottom:Color(red: 0.86, green: 0.97, blue: 0.98),
            darkWash:   Color(red: 0.18, green: 0.22, blue: 0.24),
            darkTop:    Color(red: 0.88, green: 0.97, blue: 0.98),
            darkBottom: Color(red: 0.78, green: 0.93, blue: 0.95)
        ),

        // Slate → sky/ice
        "Slate":    Trio(
            lightWash:  Color(red: 0.95, green: 0.97, blue: 1.00),
            lightTop:   Color(red: 0.96, green: 0.98, blue: 1.00),
            lightBottom:Color(red: 0.90, green: 0.95, blue: 1.00),
            darkWash:   Color(red: 0.15, green: 0.17, blue: 0.21),
            darkTop:    Color(red: 0.90, green: 0.95, blue: 1.00),
            darkBottom: Color(red: 0.82, green: 0.90, blue: 1.00)
        ),

        // Midnight → warm gold
        "Midnight": Trio(
            lightWash:  Color(red: 1.00, green: 0.96, blue: 0.90),
            lightTop:   Color(red: 1.00, green: 0.95, blue: 0.88),
            lightBottom:Color(red: 1.00, green: 0.90, blue: 0.76),
            darkWash:   Color(red: 0.24, green: 0.20, blue: 0.15),
            darkTop:    Color(red: 1.00, green: 0.91, blue: 0.79),
            darkBottom: Color(red: 1.00, green: 0.84, blue: 0.61)
        )
    ]
}

/// Apply pastel themed background and hide default list/form backing.
extension View {
    func themedSurface() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(ThemeSurfaceBackground())
    }
}
