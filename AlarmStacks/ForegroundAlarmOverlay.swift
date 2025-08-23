//
//  ForegroundAlarmOverlay.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import Combine
#if canImport(AlarmKit)
import AlarmKit
#endif

struct ForegroundAlarmOverlay: ViewModifier {
    @StateObject private var controller = AlarmController.shared

    func body(content: Content) -> some View {
        #if canImport(AlarmKit)
        ZStack {
            content
            if let ringing = controller.alertingAlarm {
                overlay(for: ringing)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
            }
        }
        .onAppear { controller.startObserversIfNeeded() }
        .animation(.spring(), value: controller.alertingAlarm?.id)
        #else
        content
        #endif
    }

    #if canImport(AlarmKit)
    @ViewBuilder
    private func overlay(for alarm: Alarm) -> some View {
        // Resolve "next up" info from the shared bridge (preferred).
        let next = NextAlarmBridge.read()

        // Fallback to metadata we persisted per-alarm when scheduling (for the CURRENT ringing alarm).
        let ud = UserDefaults.standard
        let currentStack = ud.string(forKey: "ak.stackName.\(alarm.id.uuidString)") ?? "Alarm"
        let currentStep  = ud.string(forKey: "ak.stepTitle.\(alarm.id.uuidString)") ?? "Now"

        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                // Leading: concise next-step details (no filler wording).
                VStack(alignment: .leading, spacing: 4) {
                    NextChip()

                    if let info = next {
                        Text(info.stepTitle)
                            .font(.headline)
                            .singleLineTightTail(minScale: 0.85)

                        Text(info.stackName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .singleLineTightTail(minScale: 0.85)
                    } else {
                        // If we can't determine the NEXT step, at least show what’s ringing now.
                        Text(currentStep)
                            .font(.headline)
                            .singleLineTightTail(minScale: 0.85)

                        Text(currentStack)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .singleLineTightTail(minScale: 0.85)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                // If we know the next step's time, show a compact countdown (or absolute time if overdue).
                if let info = next {
                    Group {
                        if info.fireDate > Date() {
                            Text(info.fireDate, style: .timer)
                                .monospacedDigit()
                        } else {
                            Text(info.fireDate, style: .time)
                                .monospacedDigit()
                        }
                    }
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                // STOP (prominent)
                Button {
                    AlarmController.shared.stop(alarm.id)
                } label: {
                    StopButtonLabel()
                }
                .buttonStyle(.borderedProminent)
                .layoutPriority(1)

                // SNOOZE (only if allowed)
                if alarm.countdownDuration?.postAlert != nil {
                    Button {
                        AlarmController.shared.snooze(alarm.id)
                    } label: {
                        SnoozeButtonLabel()
                    }
                    .buttonStyle(.bordered)
                    .layoutPriority(1)
                }
            }
            .padding()
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(next != nil ? "Next step" : "Current alarm"))
        .accessibilityHint(Text("Stop or snooze."))
    }
    #endif
}

#if canImport(AlarmKit)
// MARK: - Button Labels (no-wrap, icon + title)

private struct StopButtonLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "stop.circle.fill")
                .imageScale(.medium)
            Text("Stop")
                .font(.title3.bold())
                .singleLineTightTail(minScale: 0.85)
                .layoutPriority(1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }
}

private struct SnoozeButtonLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "zzz")
                .imageScale(.medium)
            Text("Snooze")
                .font(.title3.bold())
                .singleLineTightTail(minScale: 0.85)
                .layoutPriority(1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }
}

// MARK: - Small status chip (matches LA tone; no filler text)
private struct NextChip: View {
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
            .singleLineTightTail(minScale: 0.9)
    }
}
#endif

extension View {
    func alarmStopOverlay() -> some View { modifier(ForegroundAlarmOverlay()) }
}
