//
//  ThemeSurface.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI

/// Pastel, low-saturation background that adapts to the selected theme and scheme.
/// Use via `.themedSurface()` on any `List`/`Form`/scrolling surface.
struct ThemeSurfaceBackground: View {
    @AppStorage("themeName") private var themeName: String = "Default"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = scheme == .dark ? Color.black : Color(.systemGroupedBackground)
        let p = palette[themeName, default: palette["Default"]!]

        let top    = (scheme == .dark ? p.darkTop : p.lightTop)
        let bottom = (scheme == .dark ? p.darkBottom : p.lightBottom)

        ZStack {
            base
            LinearGradient(colors: [top.opacity(0.12), .clear],
                           startPoint: .top, endPoint: .center)
            RadialGradient(colors: [bottom.opacity(0.16), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 800)
        }
        .ignoresSafeArea()
    }

    // MARK: - Palette

    private struct Pair {
        let lightTop: Color, lightBottom: Color
        let darkTop: Color,  darkBottom: Color
    }

    /// Complementary pastels for each theme name.
    private let palette: [String: Pair] = [
        // Blue → warm peach/orange
        "Default":  Pair(
            lightTop:   Color(red: 1.00, green: 0.93, blue: 0.86),
            lightBottom:Color(red: 1.00, green: 0.86, blue: 0.70),
            darkTop:    Color(red: 1.00, green: 0.90, blue: 0.80),
            darkBottom: Color(red: 1.00, green: 0.82, blue: 0.62)
        ),
        // Green → pink/magenta
        "Forest":   Pair(
            lightTop:   Color(red: 1.00, green: 0.94, blue: 0.97),
            lightBottom:Color(red: 1.00, green: 0.88, blue: 0.95),
            darkTop:    Color(red: 1.00, green: 0.88, blue: 0.95),
            darkBottom: Color(red: 1.00, green: 0.78, blue: 0.90)
        ),
        // Coral → teal
        "Coral":    Pair(
            lightTop:   Color(red: 0.92, green: 0.98, blue: 0.97),
            lightBottom:Color(red: 0.84, green: 0.95, blue: 0.92),
            darkTop:    Color(red: 0.86, green: 0.96, blue: 0.94),
            darkBottom: Color(red: 0.72, green: 0.90, blue: 0.86)
        ),
        // Indigo → amber
        "Indigo":   Pair(
            lightTop:   Color(red: 1.00, green: 0.96, blue: 0.88),
            lightBottom:Color(red: 1.00, green: 0.90, blue: 0.74),
            darkTop:    Color(red: 1.00, green: 0.93, blue: 0.78),
            darkBottom: Color(red: 1.00, green: 0.86, blue: 0.62)
        ),
        // Grape → mint/lime
        "Grape":    Pair(
            lightTop:   Color(red: 0.94, green: 0.99, blue: 0.95),
            lightBottom:Color(red: 0.88, green: 0.98, blue: 0.92),
            darkTop:    Color(red: 0.88, green: 0.97, blue: 0.90),
            darkBottom: Color(red: 0.80, green: 0.94, blue: 0.84)
        ),
        // Mint → lavender
        "Mint":     Pair(
            lightTop:   Color(red: 0.96, green: 0.95, blue: 1.00),
            lightBottom:Color(red: 0.91, green: 0.90, blue: 1.00),
            darkTop:    Color(red: 0.93, green: 0.90, blue: 0.99),
            darkBottom: Color(red: 0.86, green: 0.82, blue: 0.98)
        ),
        // Pink → teal
        "Flamingo": Pair(
            lightTop:   Color(red: 0.92, green: 0.99, blue: 1.00),
            lightBottom:Color(red: 0.86, green: 0.97, blue: 0.98),
            darkTop:    Color(red: 0.88, green: 0.97, blue: 0.98),
            darkBottom: Color(red: 0.78, green: 0.93, blue: 0.95)
        ),
        // Slate → sky/ice
        "Slate":    Pair(
            lightTop:   Color(red: 0.95, green: 0.97, blue: 1.00),
            lightBottom:Color(red: 0.90, green: 0.95, blue: 1.00),
            darkTop:    Color(red: 0.90, green: 0.95, blue: 1.00),
            darkBottom: Color(red: 0.82, green: 0.90, blue: 1.00)
        ),
        // Midnight → warm gold
        "Midnight": Pair(
            lightTop:   Color(red: 1.00, green: 0.95, blue: 0.88),
            lightBottom:Color(red: 1.00, green: 0.90, blue: 0.76),
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
