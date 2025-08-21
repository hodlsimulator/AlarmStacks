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
        .onAppear { controller.startObserversIfNeeded()
            
            #if DEBUG
            LiveActivitySmokeTest.kick()
            #endif
        }
        .animation(.spring(), value: controller.alertingAlarm?.id)
        #else
        content
        #endif
    }

    #if canImport(AlarmKit)
    @ViewBuilder
    private func overlay(for alarm: Alarm) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                // Leading text compresses first so buttons never wrap
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alarm ringing")
                        .font(.headline)
                        .singleLineTightTail(minScale: 0.85)
                    Text("Tap to stop or snooze")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .singleLineTightTail(minScale: 0.85)
                }
                .layoutPriority(0)

                Spacer(minLength: 8)

                // STOP (prominent)
                Button {
                    AlarmController.shared.stop(alarm.id)
                } label: {
                    StopButtonLabel()
                }
                .buttonStyle(.borderedProminent)
                .layoutPriority(1) // keep on one line

                // SNOOZE (only if allowed)
                if alarm.countdownDuration?.postAlert != nil {
                    Button {
                        AlarmController.shared.snooze(alarm.id)
                    } label: {
                        SnoozeButtonLabel()
                    }
                    .buttonStyle(.bordered)
                    .layoutPriority(1) // keep on one line
                }
            }
            .padding()
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Controls for the currently ringing alarm.")
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
        // Prevent vertical growth that could invite wrapping
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
                .singleLineTightTail(minScale: 0.85) // tighten, then scale slightly, then ellipsis
                .layoutPriority(1)
        }
        // Prevent vertical growth that could invite wrapping
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }
}
#endif

extension View {
    func alarmStopOverlay() -> some View { modifier(ForegroundAlarmOverlay()) }
}
    
