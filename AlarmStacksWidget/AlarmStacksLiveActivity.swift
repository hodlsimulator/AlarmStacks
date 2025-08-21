//
//  AlarmStacksLiveActivity.swift
//  AlarmStacksWidget
//
//  Created by . . on 8/21/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LAChip: View {
    let hex: String
    var body: some View {
        Circle()
            .fill(Color(hex: hex) ?? .blue)
            .frame(width: 10, height: 10)
    }
}

// Tiny hex -> Color helper (safe default)
private extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF)/255
        let g = Double((v >> 8) & 0xFF)/255
        let b = Double(v & 0xFF)/255
        self = Color(red: r, green: g, blue: b)
    }
}

struct AlarmStacksLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            // Lock Screen / Banner
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LAChip(hex: context.state.accentHex)
                    Text(context.state.stackName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(context.state.stepTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("Next in")
                    Text(context.state.ends, style: .relative)
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.stepTitle).font(.headline).lineLimit(1)
                        Text(context.state.ends, style: .timer)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                LAChip(hex: context.state.accentHex)
            } compactTrailing: {
                Text(context.state.ends, style: .timer)
                    .monospacedDigit()
            } minimal: {
                LAChip(hex: context.state.accentHex)
            }
        }
    }
}
