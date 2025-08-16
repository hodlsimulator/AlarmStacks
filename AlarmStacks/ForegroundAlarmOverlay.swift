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
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alarm ringing").font(.headline)
                    Text("Tap to stop or snooze").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    AlarmController.shared.stop(alarm.id)
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill").font(.title3.bold())
                }
                .buttonStyle(.borderedProminent)

                if alarm.countdownDuration?.postAlert != nil {
                    Button {
                        AlarmController.shared.snooze(alarm.id)
                    } label: {
                        Label("Snooze", systemImage: "zzz").font(.title3.bold())
                    }
                    .buttonStyle(.bordered)
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

extension View {
    func alarmStopOverlay() -> some View { modifier(ForegroundAlarmOverlay()) }
}
