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
            date: Date(),
            info: NextAlarmInfo(stackName: "Morning",
                                stepTitle: "Coffee",
                                fireDate: Date().addingTimeInterval(900))
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(NextAlarmEntry(date: Date(), info: NextAlarmBridge.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let info = NextAlarmBridge.read()

        var entries: [NextAlarmEntry] = [NextAlarmEntry(date: Date(), info: info)]
        if let fire = info?.fireDate {
            entries.append(NextAlarmEntry(date: fire.addingTimeInterval(0.5), info: info))
            completion(Timeline(entries: entries, policy: .after(fire.addingTimeInterval(60))))
        } else {
            completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(300))))
        }
    }
}

// MARK: - Style helpers (static widget)

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

// MARK: - Widget view (static)

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
                    .singleLineTightTail()

                Text(info.stepTitle)
                    .font(.subheadline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .singleLineTightTail()

                if entry.date < info.fireDate {
                    Text(info.fireDate, style: .timer)
                        .monospacedDigit()
                        .font(timerFont)
                        .singleLineTightTail(minScale: 0.7)
                } else {
                    Text(info.fireDate, style: .time)
                        .monospacedDigit()
                        .font(timerFont.weight(.bold))
                        .singleLineTightTail(minScale: 0.7)
                }
            } else {
                Text("No upcoming step")
                    .font(.headline.weight(.semibold))
                    .fontDesign(.rounded)
                    .singleLineTightTail()
                Text("Open AlarmStacks")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .singleLineTightTail()
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
