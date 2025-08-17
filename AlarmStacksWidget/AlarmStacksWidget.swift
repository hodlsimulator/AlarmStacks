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
        let refresh = (info?.fireDate ?? Date()).addingTimeInterval(60)
        let entry = NextAlarmEntry(date: .now, info: info)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct NextAlarmWidgetView: View {
    var entry: NextAlarmProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let info = entry.info {
                Text(info.stackName).font(.headline)
                Text(info.stepTitle).font(.subheadline)
                HStack {
                    Image(systemName: "timer")
                    Text(info.fireDate, style: .relative)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text("No upcoming step").font(.headline)
                Text("Open AlarmStacks").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
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

// MARK: - Live Activity (Lock Screen + Dynamic Island with deep links)

@available(iOSApplicationExtension 16.1, *)
struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            // Lock Screen / Banner
            VStack(alignment: .leading) {
                Text(context.state.stackName).font(.headline)
                Text(context.state.stepTitle).font(.subheadline)
                HStack {
                    Image(systemName: "timer")
                    Text(context.state.ends, style: .timer)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
            .widgetURL(URL(string: "alarmstacks://activity/open"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading) {
                        Text(context.state.stackName).font(.headline)
                        Text(context.state.stepTitle).font(.subheadline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack {
                        Link(destination: URL(string: "alarmstacks://action/stop?alarmID=\(context.state.alarmID)")!) {
                            Image(systemName: "stop.fill")
                        }
                        if context.state.allowSnooze {
                            Link(destination: URL(string: "alarmstacks://action/snooze?alarmID=\(context.state.alarmID)")!) {
                                Image(systemName: "zzz")
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "timer")
                        Text(context.state.ends, style: .timer)
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
            } compactTrailing: {
                Text(context.state.ends, style: .timer)
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
