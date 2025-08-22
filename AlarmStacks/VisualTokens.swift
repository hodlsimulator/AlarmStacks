//
//  VisualTokens.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import SwiftUI

/// Elevation presets used across chips, rows, cards, and sheets.
public enum ElevationLevel {
    case chip, row, card, sheet, overlay

    var drop: (y: CGFloat, blur: CGFloat, a: CGFloat) {
        switch self {
        case .chip:   return (1, 2, 0.06)
        case .row:    return (2, 6, 0.08)
        case .card:   return (6, 18, 0.12)
        case .sheet:  return (10, 28, 0.16)
        case .overlay:return (8, 22, 0.14)
        }
    }

    var ambient: (blur: CGFloat, a: CGFloat) {
        switch self {
        case .chip:   return (1, 0.03)
        case .row:    return (2, 0.04)
        case .card:   return (8, 0.06)
        case .sheet:  return (14, 0.08)
        case .overlay:return (10, 0.07)
        }
    }
}

/// Duo-stroke parameters for glass edges.
public struct DuoStroke {
    public var keylineOpacityLight: CGFloat = 0.18
    public var keylineOpacityDark:  CGFloat = 0.28
    public var shineTopOpacity:     CGFloat = 0.35
    public var shineBottomOpacity:  CGFloat = 0.08

    public static let `default` = DuoStroke()
}

/// Helper to render a duo-stroke around a rounded shape.
public struct DuoStrokeOverlay: View {
    let radius: CGFloat
    let lineWidth: CGFloat
    let tokens: DuoStroke
    @Environment(\.colorScheme) private var scheme

    public init(radius: CGFloat, lineWidth: CGFloat = 1, tokens: DuoStroke = .default) {
        self.radius = radius
        self.lineWidth = lineWidth
        self.tokens = tokens
    }

    public var body: some View {
        let keyline = (scheme == .dark ? tokens.keylineOpacityDark : tokens.keylineOpacityLight)
        let shineTop = (scheme == .dark ? tokens.shineTopOpacity + 0.10 : tokens.shineTopOpacity)
        let shineBottom = (scheme == .dark ? tokens.shineBottomOpacity + 0.04 : tokens.shineBottomOpacity)

        return ZStack {
            // Outer keyline
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(keyline), lineWidth: lineWidth)

            // Inner shine gradient (top stronger → bottom faint)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(shineTop),
                            Color.white.opacity(shineBottom)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: lineWidth
                )
                .blendMode(.plusLighter)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

/// Drop + ambient shadow bundle for an elevation level.
public struct ElevationShadow: ViewModifier {
    let level: ElevationLevel
    @Environment(\.colorScheme) private var scheme

    public func body(content: Content) -> some View {
        let d = level.drop
        let a = level.ambient
        let darkFactor: CGFloat = (scheme == .dark) ? 0.8 : 1.0

        return content
            .shadow(color: Color.black.opacity(d.a * darkFactor), radius: d.blur, x: 0, y: d.y)
            .shadow(color: Color.black.opacity(a.a * darkFactor), radius: a.blur, x: 0, y: 0)
    }
}

public extension View {
    func elevation(_ level: ElevationLevel) -> some View { self.modifier(ElevationShadow(level: level)) }
}
