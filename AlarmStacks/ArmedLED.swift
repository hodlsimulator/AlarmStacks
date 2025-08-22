//
//  ArmedLED.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import SwiftUI

/// Tiny bright green indicator for “armed”.
struct ArmedLED: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hue: 0.33, saturation: 1.0, brightness: 1.0))  // brighter green
            Circle()
                .stroke(.white.opacity(scheme == .dark ? 0.65 : 0.9), lineWidth: 0.7)
        }
        .frame(width: 12, height: 12) // a bit bigger
        .shadow(color: .green.opacity(0.9), radius: 3.5, x: 0, y: 0) // stronger glow
        .accessibilityHidden(true)
    }
}
