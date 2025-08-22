//
//  VersionBadge.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import SwiftUI

/// Small version/build badge shown at the bottom of the home list.
struct VersionBadge: View {
    private var localVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        HStack {
            Spacer()
            Text(localVersionString)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                // Engraved effect: reversed bevel inside the glyphs
                .overlay(
                    Text(localVersionString)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.35))
                        .offset(x: -0.5, y: -0.5)
                        .blur(radius: 0.6)
                        .blendMode(.multiply)
                )
                .overlay(
                    Text(localVersionString)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .offset(x: 0.6, y: 0.6)
                        .blur(radius: 0.7)
                        .blendMode(.screen)
                )
                .compositingGroup()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Spacer()
        }
        .padding(.bottom, 6)
    }
}
