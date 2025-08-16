//
//  DebugQuickAlarm.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

struct DebugQuickAlarmButton: View {
    var body: some View {
        Menu {
            // Countdown timer: fires ~10s from now via your scheduler
            Button {
                Task {
                    let s = Stack(name: "Quick Timer",
                                  steps: [Step(title: "10s Timer",
                                               kind: .timer,
                                               order: 0,
                                               durationSeconds: 10)])
                    _ = try? await AlarmScheduler.shared.schedule(stack: s)
                }
            } label: {
                Label("Timer 10s", systemImage: "timer")
            }

            #if canImport(AlarmKit)
            // Absolute alarm at Date.now + 10s (direct AlarmKit, bypassing date maths)
            Button {
                Task {
                    do {
                        // Minimal alert + attributes
                        let alert = AlarmPresentation.Alert(
                            title: LocalizedStringResource("Quick Alarm — 10s"),
                            stopButton: AlarmButton(
                                text: LocalizedStringResource("Stop"),
                                textColor: .white,
                                systemImageName: "stop.fill"
                            ),
                            secondaryButton: AlarmButton(
                                text: LocalizedStringResource("Snooze"),
                                textColor: .white,
                                systemImageName: "zzz"
                            )
                        )

                        // Use a local metadata type to avoid any name clashes.
                        struct DebugMetadata: AlarmMetadata {}
                        let attrs = AlarmAttributes<DebugMetadata>(
                            presentation: AlarmPresentation(alert: alert),
                            tintColor: .pink
                        )

                        let id = UUID()
                        let fire = Date().addingTimeInterval(10)
                        _ = try await AlarmManager.shared.schedule(
                            id: id,
                            configuration: .alarm(
                                schedule: .fixed(fire),
                                attributes: attrs
                            )
                        )
                    } catch {
                        print("Quick absolute alarm failed: \(error)")
                    }
                }
            } label: {
                Label("Alarm 10s (absolute)", systemImage: "alarm")
            }
            #endif
        } label: {
            Label("Test Alarm", systemImage: "alarm")
        }
        .accessibilityLabel("Test Alarm")
    }
}
