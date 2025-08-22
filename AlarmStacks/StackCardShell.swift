//
//  StackCardShell.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import SwiftUI

/// Rounded “content” card – NOT glass; glass is reserved for small controls.
struct StackCardShell<Content: View>: View {
    let accent: Color
    let content: Content
    @Environment(\.colorScheme) private var scheme

    init(accent: Color, @ViewBuilder _ content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        ZStack { content.padding(8) }                // tighter padding → shorter card
            .mask(shape)                              // keep children clipped to radius
            .background {
                shape.fill(.thinMaterial).allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(accent.opacity(scheme == .dark ? 0.65 : 0.55), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.inset(by: 0.5)
                    .strokeBorder(.white.opacity(scheme == .dark ? 0.08 : 0.20), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(scheme == .dark ? 0.05 : 0.08),
                            .clear,
                            .white.opacity(scheme == .dark ? 0.03 : 0.05)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.20 : 0.10), radius: 10, x: 0, y: 6)
            .contentShape(shape) // define the tappable bounds for the row
    }
}
