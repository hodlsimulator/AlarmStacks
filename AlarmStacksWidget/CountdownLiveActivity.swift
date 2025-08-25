//
//  CountdownLiveActivity.swift
//  AlarmStacks
//
//  Created by . . on 8/25/25.
//

import WidgetKit
import SwiftUI
import ActivityKit
import AlarmKit

/// Add this widget to your existing WidgetBundle.
/// Do NOT call Activity.request() anywhere; AlarmKit drives the Activity.
struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TimerLAMetadata>.self) { context in
            CountdownTextView(state: context.state)
                .font(.largeTitle.weight(.bold))
                .monospacedDigit()
                .padding()
                .tint(context.attributes.tintColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        CountdownTextView(state: context.state).font(.headline)
                        CountdownProgressView(state: context.state).frame(maxHeight: 28)
                    }
                }
            } compactLeading: {
                CountdownTextView(state: context.state)
            } compactTrailing: {
                CountdownProgressView(state: context.state)
            } minimal: {
                CountdownProgressView(state: context.state)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }
}

private struct CountdownTextView: View {
    let state: AlarmPresentationState
    var body: some View {
        if case let .countdown(c) = state.mode {
            Text(timerInterval: Date.now ... c.fireDate)
                .monospacedDigit()
        } else if case .paused = state.mode {
            Text("Paused")
        } else {
            // Covers the alerting/post-alert states without pattern-matching a case that may differ by OS seed.
            Text("Ringing")
        }
    }
}

private struct CountdownProgressView: View {
    let state: AlarmPresentationState
    var body: some View {
        if case let .countdown(c) = state.mode {
            ProgressView(timerInterval: Date.now ... c.fireDate) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
            .progressViewStyle(.circular)
        }
    }
}
