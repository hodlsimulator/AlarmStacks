//
//  AlarmStacksWidget.swift
//  AlarmStacksWidget
//  Created by . . on 8/17/25.
//

import WidgetKit
import SwiftUI
import Foundation
import ActivityKit
#if canImport(UIKit)
import UIKit
#endif

// Shared tolerance to avoid flapping exactly at the boundary.
// Timer only when target is in the future by more than this epsilon.
private let TIMER_EPSILON: TimeInterval = 0.4

// MARK: - Static widget
struct NextAlarmEntry: TimelineEntry { let date: Date; let info: NextAlarmInfo? }

struct NextAlarmProvider: TimelineProvider {
    func placeholder(in: Context) -> NextAlarmEntry {
        .init(date: .now, info: .init(stackName: "Morning", stepTitle: "Coffee", fireDate: .now.addingTimeInterval(900)))
    }
    func getSnapshot(in: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(.init(date: .now, info: NextAlarmBridge.read()))
    }
    func getTimeline(in: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let info = NextAlarmBridge.read()
        var entries = [NextAlarmEntry(date: .now, info: info)]
        if let fire = info?.fireDate {
            // Add a post-fire tick so we flip to absolute time and never count up.
            entries.append(.init(date: fire.addingTimeInterval(0.5), info: info))
            completion(.init(entries: entries, policy: .after(fire.addingTimeInterval(60))))
        } else {
            completion(.init(entries: entries, policy: .after(Date().addingTimeInterval(300))))
        }
    }
}

// Small card style (used only by the static widget)
private struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            )
    }
}

private struct ContainerBG: ViewModifier {
    let color: Color
    func body(content: Content) -> some View { content.containerBackground(color, for: .widget) }
}

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

    // Read current theme from App Group (for static widget background)
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
                Text(info.stackName).font(.headline.weight(.semibold)).fontDesign(.rounded).singleLineTightTail()
                Text(info.stepTitle).font(.subheadline).fontDesign(.rounded).foregroundStyle(.secondary).singleLineTightTail()

                // Static widget: never let the timer count up — use epsilon.
                if info.fireDate.timeIntervalSince(entry.date) > TIMER_EPSILON {
                    Text(info.fireDate, style: .timer).monospacedDigit().font(timerFont).singleLineTightTail(minScale: 0.7)
                } else {
                    Text(info.fireDate, style: .time).monospacedDigit().font(timerFont.weight(.bold)).singleLineTightTail(minScale: 0.7)
                }
            } else {
                Text("No upcoming step").font(.headline.weight(.semibold)).fontDesign(.rounded).singleLineTightTail()
                Text("Open AlarmStacks").font(.footnote).foregroundStyle(.secondary).singleLineTightTail()
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

// === Live Activity ===

fileprivate struct LATimeDecider {
    static func isPreFire(_ ends: Date, now: Date = .init()) -> Bool {
        return ends.timeIntervalSince(now) > TIMER_EPSILON
    }
    static func mode(for state: AlarmActivityAttributes.ContentState, now: Date = .init())
      -> (chip: String, useTimer: Bool, clockDate: Date, timerTo: Date)
    {
        let pre = isPreFire(state.ends, now: now)
        if pre {
            return ("NEXT STEP", true, state.ends, state.ends)
        } else {
            if let fired = state.firedAt {
                return ("RINGING", false, fired, state.ends)
            } else {
                return ("NEXT STEP", false, state.ends, state.ends)
            }
        }
    }
}

// Make timer digits look “right” (less blocky than .heavy)
fileprivate enum TimerStyle {
    static let lockFont   : Font = .system(size: 52, weight: .bold,  design: .rounded)
    static let islandFont : Font = .system(size: 34, weight: .bold,  design: .rounded)
    static func isTimer(_ s: AlarmActivityAttributes.ContentState) -> Bool {
        s.stackName.hasPrefix("⏱") || s.stepTitle.lowercased() == "timer"
    }
}

private struct AlarmActivityLockRoot: View {
    let context: ActivityViewContext<AlarmActivityAttributes>

    var body: some View {
        let accent = context.state.theme.accent.color
        let m = LATimeDecider.mode(for: context.state)
        let isTimer = TimerStyle.isTimer(context.state)

        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(m.chip)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.20), lineWidth: 1)
                        )
                        .singleLineTightTail()

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

                Group {
                    if m.useTimer {
                        Text(m.timerTo, style: .timer).monospacedDigit()
                    } else {
                        Text(m.clockDate, style: .time).monospacedDigit()
                    }
                }
                .font(isTimer ? TimerStyle.lockFont : .title.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .tint(accent)
        .activityBackgroundTint(.clear)
        .activitySystemActionForegroundColor(.primary)
        .widgetURL(URL(string: "alarmstacks://activity/open"))
    }
}

struct AlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            AlarmActivityLockRoot(context: context)
        } dynamicIsland: { context in
            let accent = context.state.theme.accent.color
            let m = LATimeDecider.mode(for: context.state)
            let isTimer = TimerStyle.isTimer(context.state)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill").foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.chip)
                            .font(.caption2.weight(.semibold))
                            .tracking(0.8)
                            .singleLineTightTail()
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
                }
                DynamicIslandExpandedRegion(.trailing) { EmptyView() }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Group {
                            if m.useTimer {
                                Text(m.timerTo, style: .timer).monospacedDigit()
                            } else {
                                Text(m.clockDate, style: .time).monospacedDigit()
                            }
                        }
                        .font(isTimer ? TimerStyle.islandFont : .title3.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(accent)
            } compactTrailing: {
                Group {
                    if m.useTimer {
                        Text(m.timerTo, style: .timer).monospacedDigit()
                    } else {
                        Text(m.clockDate, style: .time).monospacedDigit()
                    }
                }
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

@main
struct AlarmStacksWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        AlarmActivityWidget()
        // ⛔️ Do NOT include any separate Timer LA widget — this keeps only one LA.
    }
}
