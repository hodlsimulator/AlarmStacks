//
//  CardStyle.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import SwiftUI

// MARK: - Liquid Glass (capsule) for compact controls

enum LiquidGlassVariant { case regular, clear }

private struct LiquidGlassCapsuleModifier: ViewModifier {
    var variant: LiquidGlassVariant = .regular
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)
        let base: AnyShapeStyle = (variant == .regular) ? AnyShapeStyle(.thinMaterial)
                                                        : AnyShapeStyle(.ultraThinMaterial)

        // Edge treatments
        let depthStroke  = Color.primary.opacity(scheme == .dark ? 0.28 : 0.20)
        let innerShine   = Color.white.opacity(scheme == .dark ? 0.10 : 0.22)
        let specularTop  = Color.white.opacity(scheme == .dark ? 0.05 : 0.08)
        let specularTail = Color.white.opacity(scheme == .dark ? 0.03 : 0.05)

        content
            .background {
                shape.fill(base).allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(depthStroke, lineWidth: 1).allowsHitTesting(false)
            }
            .overlay {
                shape.inset(by: 0.5).strokeBorder(innerShine, lineWidth: 0.75).allowsHitTesting(false)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [specularTop, .clear, specularTail],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .contentShape(shape)
    }
}

extension View {
    /// iOS 26-style Liquid Glass capsule for compact controls.
    func liquidGlassCapsule(_ variant: LiquidGlassVariant = .regular) -> some View {
        modifier(LiquidGlassCapsuleModifier(variant: variant))
    }
}

// MARK: - Glassy step chip (shared token)

struct GlassChipModifier: ViewModifier {
    enum State { case normal, disabled, legacy }
    let state: State
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)
        let neutralStroke = Color.primary.opacity(scheme == .dark ? 0.25 : 0.18)
        let legacyStroke  = Color.orange.opacity(scheme == .dark ? 0.55 : 0.45)
        let strokeColor   = (state == .legacy) ? legacyStroke : neutralStroke
        let innerShine    = Color.white.opacity(scheme == .dark ? 0.08 : 0.20)
        let opacity: CGFloat = (state == .disabled) ? 0.55 : 1.0

        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                shape.fill(.thinMaterial).allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(strokeColor, lineWidth: 1).allowsHitTesting(false)
            }
            .overlay {
                shape.inset(by: 0.5).strokeBorder(innerShine, lineWidth: 0.75).allowsHitTesting(false)
            }
            .opacity(opacity)
            .contentShape(shape)
    }
}

extension View {
    func glassChip(state: GlassChipModifier.State = .normal) -> some View {
        modifier(GlassChipModifier(state: state))
    }
}
