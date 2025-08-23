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

// MARK: - Shared bridge model (static widget)
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

        var entries: [NextAlarmEntry] = [NextAlarmEntry(date: .now, info: info)]
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
        content.containerBackground(color, for: .widget)
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

#if canImport(ActivityKit)
// MARK: - LA view logger (writes to App Group so the app can read it)

private enum LAViewLogger {
    private static let logKey = "diag.log.lines"

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        return f
    }()

    private static func append(_ line: String) {
        let now = Date()
        let up  = ProcessInfo.processInfo.systemUptime
        let stamp = "\(fmt.string(from: now)) | up:\(String(format: "%.3f", up))s"
        let full = "[\(stamp)] \(line)"
        let ud = UserDefaults(suiteName: AppGroups.main)
        var lines = ud?.stringArray(forKey: logKey) ?? []
        lines.append(full)
        if lines.count > 2000 {
            lines.removeFirst(lines.count - 2000)
        }
        ud?.set(lines, forKey: logKey)
    }

    /// Throttled log of exactly what the LA is showing.
    static func logRender(surface: String, state: AlarmActivityAttributes.ContentState) {
        let now = Date()
        let mode: String
        var bucket = 0
        if state.ends > now {
            let remain = Int(round(state.ends.timeIntervalSince(now)))
            bucket = max(0, remain / 30) // 30s buckets
            mode = "timer(remaining=\(remain)s)"
        } else {
            mode = "time(ends=\(fmt.string(from: state.ends)))"
        }

        // Throttle by alarmID + surface + bucket.
        let sig = "\(state.alarmID)|\(surface)|\(mode)|\(bucket)"
        let sigKey = "la.lastsig.\(state.alarmID).\(surface)"
        let ud = UserDefaults(suiteName: AppGroups.main)
        let last = ud?.string(forKey: sigKey)
        if last == sig { return }
        ud?.set(sig, forKey: sigKey)

        append("[LA] render surface=\(surface) stack=\(state.stackName) step=\(state.stepTitle) status=Next mode=\(mode) ends=\(fmt.string(from: state.ends)) now=\(fmt.string(from: now)) id=\(state.alarmID.isEmpty ? "-" : state.alarmID)")
    }
}

// MARK: - Small accent glyph (stroke-only, no opaque fill)

private struct GlassGlyph: View {
    let accent: Color
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(accent.opacity(0.28), lineWidth: 1.5)
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .frame(width: 34, height: 34)
            Image(systemName: "alarm.fill")
                .imageScale(.medium)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
        }
    }
}

// Small glassy status capsule (always “Next step”)
private struct StatusChip: View {
    var body: some View {
        Text("NEXT STEP")
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.clear)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.20), lineWidth: 1)
                    )
            )
            .singleLineTightTail()
    }
}

// MARK: - Live Activity (Lock screen root)

private struct AlarmActivityLockRoot: View {
    let context: ActivityViewContext<AlarmActivityAttributes>

    /// Always present the next step + countdown (never “Ringing” text).
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                GlassGlyph(accent: context.state.theme.accent.color)

                VStack(alignment: .leading, spacing: 4) {
                    StatusChip()
                    Text(context.state.stackName)
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                        .singleLineTightTail()
                    Text(context.state.stepTitle)
                        .font(.body)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .singleLineTightTail()
                }

                Spacer(minLength: 8)

                // Prefer countdown; fall back to absolute time if we’re at/past ends.
                Group {
                    if context.state.ends > Date() {
                        Text(context.state.ends, style: .timer).monospacedDigit()
                    } else {
                        Text(context.state.ends, style: .time).monospacedDigit()
                    }
                }
                .font(.title.weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .applyLiveActivityTheme()                   // <- theme/tints live here
        .activitySystemActionForegroundColor(.primary)
        .widgetURL(URL(string: "alarmstacks://activity/open"))
        .onAppear { LAViewLogger.logRender(surface: "lock", state: context.state) }
        .onChange(of: context.state) { _, newState in
            LAViewLogger.logRender(surface: "lock", state: newState)
        }
    }
}

// MARK: - Activity + Island

struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            AlarmActivityLockRoot(context: context)
        } dynamicIsland: { context in
            let accent = context.state.theme.accent.color

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GlassGlyph(accent: accent)
                        .onAppear { LAViewLogger.logRender(surface: "island.expanded", state: context.state) }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        StatusChip()
                        Text(context.state.stackName)
                            .font(.headline.weight(.semibold))
                            .fontDesign(.rounded)
                            .singleLineTightTail()
                        Text(context.state.stepTitle)
                            .font(.subheadline)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                            .singleLineTightTail()
                    }
                    .onAppear { LAViewLogger.logRender(surface: "island.expanded", state: context.state) }
                    .onChange(of: context.state) { _, newState in
                        LAViewLogger.logRender(surface: "island.expanded", state: newState)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView() // no Stop/Snooze icons in the island
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Group {
                            if context.state.ends > Date() {
                                Text(context.state.ends, style: .timer)
                                    .monospacedDigit()
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                            } else {
                                Text(context.state.ends, style: .time).monospacedDigit()
                            }
                        }
                        .font(.title3.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(accent)
                    .onAppear { LAViewLogger.logRender(surface: "island.compactLeading", state: context.state) }
            } compactTrailing: {
                Group {
                    if context.state.ends > Date() {
                        Text(context.state.ends, style: .timer).monospacedDigit()
                    } else {
                        Text(context.state.ends, style: .time).monospacedDigit()
                    }
                }
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                .onAppear { LAViewLogger.logRender(surface: "island.compactTrailing", state: context.state) }
                .onChange(of: context.state) { _, newState in
                    LAViewLogger.logRender(surface: "island.compactTrailing", state: newState)
                }
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(accent)
                    .onAppear { LAViewLogger.logRender(surface: "island.minimal", state: context.state) }
            }
            .keylineTint(accent)
        }
    }
}
#endif

@main
struct AlarmStacksWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        #if canImport(ActivityKit)
        AlarmActivityWidget()
        #endif
    }
}
