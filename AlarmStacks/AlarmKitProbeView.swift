//
//  AlarmKitProbeView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

#if canImport(AlarmKit)
import SwiftUI
import AlarmKit

/// Tiny on-device probe to verify scheduling and observe active alarms.
struct AlarmKitProbeView: View {
    @State private var alarmIDs: [UUID] = []
    @State private var activeAlarms: [Alarm] = []

    var body: some View {
        VStack(spacing: 16) {
            Button("Schedule 5s Test Alarm") {
                Task {
                    let s = Stack(
                        name: "Debug Probe",
                        steps: [
                            Step(title: "Test 5s", kind: .timer, order: 0, durationSeconds: 5)
                        ]
                    )
                    do {
                        let ids = try await AlarmScheduler.shared.schedule(stack: s)
                        alarmIDs = ids.compactMap(UUID.init(uuidString:))
                    } catch {
                        print("Probe schedule error: \(error)")
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            List {
                Section("Last Scheduled IDs") {
                    if alarmIDs.isEmpty {
                        Text("None yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(alarmIDs, id: \.self) { id in
                            Text(id.uuidString)
                                .font(.footnote)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Active Alarms (live)") {
                    if activeAlarms.isEmpty {
                        Text("No active alarms")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeAlarms, id: \.id) { alarm in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(alarm.id.uuidString)
                                    .font(.footnote)
                                    .lineLimit(1)
                                    .textSelection(.enabled)

                                Text(stateLabel(for: alarm.state))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .task {
            // Request permission once.
            try? await AlarmScheduler.shared.requestAuthorizationIfNeeded()
        }
        .task {
            // Poll alarms once per second; `alarms` is throwing (not async).
            while !Task.isCancelled {
                do {
                    activeAlarms = try AlarmManager.shared.alarms
                } catch {
                    activeAlarms = []
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .padding()
    }

    private func stateLabel(for state: Alarm.State) -> String {
        switch state {
        case .scheduled: return "Scheduled"
        case .countdown: return "Counting down"
        case .alerting:  return "Alerting"
        case .paused:    return "Paused"
        @unknown default: return "Unknown"
        }
    }
}
#endif
    