//
//  AlarmStacksWidget.swift
//  AlarmStacksWidget
//  Created by . . on 8/17/25.
//

import WidgetKit
import SwiftUI
import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Shared bridge model
struct NextAlarmEntry: TimelineEntry {
    let date: Date
    let info: NextAlarmInfo?
}

struct NextAlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(date: .now, info: .init(stackName: "Morning", stepTitle: "Coffee", fireDate: .now.addingTimeInterval(900)))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(NextAlarmEntry(date: .now, info: NextAlarmBridge.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let info = NextAlarmBridge.read()
        // Refresh shortly after the fire date so we flip to “Now” promptly.
        let refresh = (info?.fireDate ?? Date()).addingTimeInterval(30)
        completion(Timeline(entries: [NextAlarmEntry(date: .now, info: info)], policy: .after(refresh)))
    }
}

// MARK: - Style helpers

private struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            )
    }
}

private struct TimerLabel: View {
    let ends: Date
    let font: Font
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").imageScale(.medium)
            if ends > Date() {
                Text(ends, style: .timer).monospacedDigit().font(font)
            } else {
                Text("Now").monospaced().font(font)
            }
        }
    }
}

private struct ContainerBG: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(.fill.tertiary, for: .widget)
        } else {
            content
        }
    }
}

// MARK: - Widget view

struct NextAlarmWidgetView: View {
    var entry: NextAlarmProvider.Entry
    @Environment(\.widgetFamily) private var family

    private var timerFont: Font {
        switch family {
        case .systemSmall: return .title3.weight(.semibold)
        case .systemMedium: return .title2.weight(.semibold)
        case .accessoryRectangular: return .body.weight(.semibold)
        default: return .title3.weight(.semibold)
        }
    }

    var body: some View {
        Card {
            if let info = entry.info {
                Text(info.stackName)
                    .font(.headline.weight(.semibold))
                    .fontDesign(.rounded)
                Text(info.stepTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fontDesign(.rounded)

                TimerLabel(ends: info.fireDate, font: timerFont)
                    .foregroundStyle(.primary)
            } else {
                Text("No upcoming step")
                    .font(.headline.weight(.semibold))
                    .fontDesign(.rounded)
                Text("Open AlarmStacks")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .modifier(ContainerBG())
    }
}

struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextAlarmWidget", provider: NextAlarmProvider()) { entry in
            NextAlarmWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Alarm Step")
        .description("Shows the next step and countdown.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Live Activity (Lock Screen + Dynamic Island)

@available(iOSApplicationExtension 16.1, *)
struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            // Lock Screen / banner: bigger digits, subdued chrome
            VStack(alignment: .leading, spacing: 8) {
                Text(context.state.stackName)
                    .font(.headline.weight(.semibold))
                    .fontDesign(.rounded)
                Text(context.state.stepTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fontDesign(.rounded)

                // Large, clear timer
                if context.state.ends > Date() {
                    Text(context.state.ends, style: .timer)
                        .monospacedDigit()
                        .font(.title.weight(.bold))
                } else {
                    Text("Now")
                        .monospaced()
                        .font(.title.weight(.bold))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .activityBackgroundTint(.secondary.opacity(0.15))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "alarmstacks://activity/open"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .imageScale(.large)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.stackName)
                            .font(.headline.weight(.semibold))
                            .fontDesign(.rounded)
                        Text(context.state.stepTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fontDesign(.rounded)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 12) {
                        Link(destination: URL(string: "alarmstacks://action/stop?alarmID=\(context.state.alarmID)")!) {
                            Image(systemName: "stop.fill").font(.title3.weight(.semibold))
                        }
                        if context.state.allowSnooze {
                            Link(destination: URL(string: "alarmstacks://action/snooze?alarmID=\(context.state.alarmID)")!) {
                                Image(systemName: "zzz").font(.title3.weight(.semibold))
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.ends > Date() {
                            Text(context.state.ends, style: .timer)
                                .monospacedDigit()
                                .font(.title3.weight(.semibold))
                        } else {
                            Text("Now")
                                .monospaced()
                                .font(.title3.weight(.semibold))
                        }
                        Spacer(minLength: 0)
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
            } compactTrailing: {
                if context.state.ends > Date() {
                    Text(context.state.ends, style: .timer).monospacedDigit()
                } else {
                    Text("Now").monospaced()
                }
            } minimal: {
                Image(systemName: "alarm.fill")
            }
        }
    }
}

@main
struct AlarmStacksWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        if #available(iOSApplicationExtension 16.1, *) {
            AlarmActivityWidget()
        }
    }
}
