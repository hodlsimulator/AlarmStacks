//
//  AlarmDiagnosticsView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import UIKit
#if canImport(AlarmKit)
import AlarmKit
#endif

struct AlarmDiagnosticsView: View {
    @State private var osVersion = UIDevice.current.systemVersion
    @State private var akState: String = "unknown"
    @State private var infoPlistValue: String = "(missing)"
    @State private var lastResult: String = ""
    @State private var scheduledIDs: [UUID] = []

    var body: some View {
        List {
            Section("Status") {
                Text("iOS \(osVersion)")
                Text("NSAlarmKitUsageDescription: \(infoPlistValue)")
                Text("Alarm auth: \(akState)")
            }

            #if canImport(AlarmKit)
            Section("AlarmKit — direct tests") {
                Button("AK Timer 15s — Stop only") { Task { await scheduleAKTimer(seconds: 15, snooze: false) } }
                Button("AK Timer 15s — Snooze")     { Task { await scheduleAKTimer(seconds: 15, snooze: true) } }
                Button("AK Timer 65s — Stop only") { Task { await scheduleAKTimer(seconds: 65, snooze: false) } }
                Button("Cancel All AK")            { Task { await cancelAllAK() } }
                if !scheduledIDs.isEmpty {
                    ForEach(scheduledIDs, id: \.self) { id in
                        Text(id.uuidString)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            #else
            Section("AlarmKit") { Text("AlarmKit not available in this build.") }
            #endif

            Section("Result") { Text(lastResult).font(.footnote) }
        }
        .navigationTitle("Diagnostics")
        .task {
            infoPlistValue = Bundle.main.object(forInfoDictionaryKey: "NSAlarmKitUsageDescription") as? String ?? "(missing)"
            #if canImport(AlarmKit)
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                akState = "\(state)"
            } catch {
                akState = "error: \(error.localizedDescription)"
            }
            #endif
        }
    }

    #if canImport(AlarmKit)
    private func makeAttrs(title: String, snooze: Bool) -> AlarmAttributes<DebugMetadata> {
        let stop = AlarmButton(
            text: LocalizedStringResource("Stop"),
            textColor: .white,
            systemImageName: "stop.fill"
        )
        let alert: AlarmPresentation.Alert
        if snooze {
            let s = AlarmButton(
                text: LocalizedStringResource("Snooze"),
                textColor: .white,
                systemImageName: "zzz"
            )
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: stop,
                secondaryButton: s,
                secondaryButtonBehavior: .countdown  // ⬅️ critical
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: stop,
                secondaryButton: nil,
                secondaryButtonBehavior: nil
            )
        }
        return AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .pink
        )
    }

    private func scheduleAKTimer(seconds: Int, snooze: Bool) async {
        let id = UUID()
        do {
            let attrs = makeAttrs(title: "Diagnostics \(seconds)s", snooze: snooze)
            let cfg: AlarmManager.AlarmConfiguration<DebugMetadata> =
                .timer(duration: TimeInterval(seconds), attributes: attrs)
            _ = try await AlarmManager.shared.schedule(id: id, configuration: cfg)
            scheduledIDs.append(id)
            lastResult = "AK TIMER scheduled id=\(id.uuidString) in \(seconds)s (snooze=\(snooze))"
        } catch {
            lastResult = "AK schedule error: \(String(describing: error))"
        }
    }

    private func cancelAllAK() async {
        for id in scheduledIDs { try? AlarmManager.shared.cancel(id: id) }
        scheduledIDs.removeAll()
        lastResult = "Cancelled locally-tracked AK IDs."
    }

    nonisolated struct DebugMetadata: AlarmMetadata {}
    #endif
}
