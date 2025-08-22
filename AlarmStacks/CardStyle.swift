//
//  CardStyle.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import SwiftUI

/// Glass card with duo-stroke and elevation.
/// Use for list cards, panels, and most containers.
public struct GlassCardModifier: ViewModifier {
    let radius: CGFloat
    let level: ElevationLevel
    let material: Material

    public init(radius: CGFloat = 18, level: ElevationLevel = .card, material: Material = .thin) {
        self.radius = radius
        self.level = level
        self.material = material
    }

    public func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(material)
            )
            .overlay(DuoStrokeOverlay(radius: radius))
            .elevation(level)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Capsule-chip variant used for step chips and small badges.
public struct GlassChipModifier: ViewModifier {
    public enum State { case normal, disabled, legacy }

    let state: State
    let material: Material

    @Environment(\.colorScheme) private var scheme
    @AppStorage("themeName") private var themeName: String = "Default"

    public init(state: State = .normal, material: Material = .ultraThin) {
        self.state = state
        self.material = material
    }

    public func body(content: Content) -> some View {
        // Derive accent from your theme map (no Environment.tint read needed).
        let accent = ThemeMap.accent(for: themeName)

        let tintAlphaLight: CGFloat = (state == .disabled) ? 0.06 : (state == .legacy ? 0.14 : 0.12)
        let tintAlphaDark:  CGFloat = (state == .disabled) ? 0.10 : (state == .legacy ? 0.18 : 0.18)
        let bg = (scheme == .dark ? accent.opacity(tintAlphaDark) : accent.opacity(tintAlphaLight))

        return content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(material)
                    .background(Capsule(style: .continuous).fill(bg))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.26 : 0.20), lineWidth: 1)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(scheme == .dark ? 0.45 : 0.35),
                                     Color.white.opacity(scheme == .dark ? 0.12 : 0.08)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .blendMode(.plusLighter)
            )
            .elevation(.chip)
            .opacity(state == .disabled ? 0.85 : 1.0)
    }
}

public extension View {
    func glassCard(radius: CGFloat = 18, level: ElevationLevel = .card, material: Material = .thin) -> some View {
        self.modifier(GlassCardModifier(radius: radius, level: level, material: material))
    }

    func glassChip(state: GlassChipModifier.State = .normal, material: Material = .ultraThin) -> some View {
        self.modifier(GlassChipModifier(state: state, material: material))
    }
}
