//
//  TimerLiveActivityWidget.swift
//  AlarmStacks
//
//  Created by . . on 8/25/25.
//

import WidgetKit
import SwiftUI
import ActivityKit

@available(iOS 16.2, *)
struct TimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock Screen
            VStack(spacing: 6) {
                Text(context.attributes.title)
                    .font(.headline)
                if let end = context.state.endDate, !context.state.isPaused {
                    Text(end, style: .timer)
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                } else {
                    Text(format(seconds: context.state.remainingSeconds))
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 8)
            .activityBackgroundTint(.clear)
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    if let end = context.state.endDate, !context.state.isPaused {
                        Text(end, style: .timer)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text(format(seconds: context.state.remainingSeconds))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                if let end = context.state.endDate, !context.state.isPaused {
                    Text(end, style: .timer).monospacedDigit()
                } else {
                    Text(short(seconds: context.state.remainingSeconds)).monospacedDigit()
                }
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }

    private func format(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func short(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):" + String(format: "%02d", s)
    }
}
