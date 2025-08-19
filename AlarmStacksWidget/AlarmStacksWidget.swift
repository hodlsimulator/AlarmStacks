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
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shared bridge model
struct NextAlarmEntry: TimelineEntry {
    let date: Date
    let info: NextAlarmInfo?
}

struct NextAlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(
            date: .now,
            info: .init(stackName: "Morning", stepTitle: "Coffee", fireDate: .now.addingTimeInterval(900))
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(NextAlarmEntry(date: .now, info: NextAlarmBridge.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let info = NextAlarmBridge.read()

        // We emit TWO entries so the widget flips from countdown to fixed time
        // right after the fire time (no count-up).
        var entries: [NextAlarmEntry] = [NextAlarmEntry(date: .now, info: info)]
        if let fire = info?.fireDate {
            entries.append(NextAlarmEntry(date: fire.addingTimeInterval(0.5), info: info))
            completion(Timeline(entries: entries, policy: .after(fire.addingTimeInterval(60))))
        } else {
            completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(300))))
        }
    }
}

// MARK: - Style helpers

private struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}

private struct ContainerBG: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(color, for: .widget)
        } else {
            content.background(color)
        }
    }
}

// MARK: - Widget view

struct NextAlarmWidgetView: View {
    var entry: NextAlarmProvider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme)  private var scheme

    private var timerFont: Font {
        switch family {
        case .systemSmall: return .title3.weight(.semibold)
        case .systemMedium: return .title2.weight(.semibold)
        case .accessoryRectangular: return .body.weight(.semibold)
        default: return .title3.weight(.semibold)
        }
    }

    // Read current theme from App Group (fallback path for static widget)
    private var theme: ThemePayload {
        let name = UserDefaults(suiteName: AppGroups.main)?
            .string(forKey: "themeName") ?? "Default"
        return ThemeMap.payload(for: name)
    }

    private var accent: Color { theme.accent.color }
    private var bg: Color { scheme == .dark ? theme.bgDark.color : theme.bgLight.color }

    var body: some View {
        Card {
            if let info = entry.info {
                Text(info.stackName)
                    .font(.headline.weight(.semibold))
                    .fontDesign(.rounded)
                    .lineLimit(1)

                Text(info.stepTitle)
                    .font(.subheadline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Use the ENTRY time (not Date()) so we never count up.
                if entry.date < info.fireDate {
                    Text(info.fireDate, style: .timer)
                        .monospacedDigit()
                        .font(timerFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    // After it fires, show the time it rang (fixed clock), not "ago".
                    Text(info.fireDate, style: .time)
                        .font(timerFont.weight(.bold))
                        .lineLimit(1)
                }
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
        .modifier(ContainerBG(color: bg))
        .tint(accent)
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

// MARK: - Live Activity

#if canImport(ActivityKit)
@available(iOSApplicationExtension 16.1, *)
private struct AlarmActivityLockRoot: View {
    let context: ActivityViewContext<AlarmActivityAttributes>
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { context.state.theme.accent.color }
    private var bg: Color {
        (scheme == .dark ? context.state.theme.bgDark.color : context.state.theme.bgLight.color)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.stackName)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .lineLimit(1)
                Text(context.state.stepTitle)
                    .font(.body)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            if let fired = context.state.firedAt {
                Text(fired, style: .time)
                    .monospaced()
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.trailing)
            } else if context.state.ends > Date() {
                Text(context.state.ends, style: .timer)
                    .monospacedDigit()
                    .font(.title.weight(.bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(context.state.ends, style: .time)
                    .monospaced()
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .tint(accent)
        .activityBackgroundTint(bg)                    // Allowed on Lock Screen view
        .activitySystemActionForegroundColor(.primary)
        .widgetURL(URL(string: "alarmstacks://activity/open"))
    }
}
#endif

@available(iOSApplicationExtension 16.1, *)
struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            #if canImport(ActivityKit)
            AlarmActivityLockRoot(context: context)
            #else
            EmptyView()
            #endif
        } dynamicIsland: { context in
            #if canImport(ActivityKit)
            let accent = context.state.theme.accent.color

            // Dynamic background that adapts to light/dark (island doesn’t support activityBackgroundTint)
            #if canImport(UIKit)
            let bg = Color(UIColor { trait in
                let isDark = (trait.userInterfaceStyle == .dark)
                return isDark
                ? UIColor(context.state.theme.bgDark.color)
                : UIColor(context.state.theme.bgLight.color)
            })
            #else
            let bg = context.state.theme.bgLight.color
            #endif

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .imageScale(.large)
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.stackName)
                            .font(.headline.weight(.semibold))
                            .fontDesign(.rounded)
                            .lineLimit(1)
                        Text(context.state.stepTitle)
                            .font(.subheadline)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
                    .tint(accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let fired = context.state.firedAt {
                            Text(fired, style: .time)
                                .monospaced()
                                .font(.title3.weight(.semibold))
                        } else if context.state.ends > Date() {
                            Text(context.state.ends, style: .timer)
                                .monospacedDigit()
                                .font(.title3.weight(.semibold))
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        } else {
                            Text(context.state.ends, style: .time)
                                .monospaced()
                                .font(.title3.weight(.semibold))
                        }
                        Spacer(minLength: 0)
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(accent)
            } compactTrailing: {
                if let fired = context.state.firedAt {
                    Text(fired, style: .time).monospaced()
                } else if context.state.ends > Date() {
                    Text(context.state.ends, style: .timer).monospacedDigit()
                } else {
                    Text(context.state.ends, style: .time).monospaced()
                }
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(accent)
            }
            .keylineTint(accent)                          // Allowed on DynamicIsland
            // No .activityBackgroundTint here (not supported on DynamicIsland)
            #else
            DynamicIsland {}
            #endif
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
    