//
//  StepEditorView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData

struct StepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var step: Step

    @State private var title: String = ""
    @State private var kind: StepKind = .fixedTime
    @State private var hour: Int = Calendar.current.component(.hour, from: Date())
    @State private var minute: Int = Calendar.current.component(.minute, from: Date())
    @State private var minutesAmount: Int = 10
    @State private var allowSnooze: Bool = true
    @State private var snoozeMinutes: Int = 9
    @State private var enabled: Bool = true
    @State private var soundName: String = ""

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Title", text: $title)
                Toggle("Enabled", isOn: $enabled)
                Picker("Kind", selection: $kind) {
                    Text("Fixed time").tag(StepKind.fixedTime)
                    Text("Timer").tag(StepKind.timer)
                    Text("After previous").tag(StepKind.relativeToPrev)
                }
            }

            if kind == .fixedTime {
                Section("Time") {
                    Stepper(value: $hour, in: 0...23) { Text("Hour: \(hour)") }
                    Stepper(value: $minute, in: 0...59) { Text("Minute: \(minute)") }
                }
            } else {
                Section(kind == .timer ? "Duration" : "Offset") {
                    Stepper(value: $minutesAmount, in: 1...240) { Text("\(minutesAmount) minutes") }
                }
            }

            Section("Behaviour") {
                Toggle("Allow Snooze", isOn: $allowSnooze)
                Stepper(value: $snoozeMinutes, in: 1...30) { Text("Snooze Minutes: \(snoozeMinutes)") }
                TextField("Sound (optional)", text: $soundName)
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("Edit Step")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    applyEdits()
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { seedFromModel() }
    }

    private func seedFromModel() {
        title = step.title
        kind = step.kind
        enabled = step.isEnabled
        hour = step.hour ?? hour
        minute = step.minute ?? minute
        if let s = step.durationSeconds { minutesAmount = max(1, s / 60) }
        if let o = step.offsetSeconds { minutesAmount = max(1, abs(o) / 60) }
        allowSnooze = step.allowSnooze
        snoozeMinutes = step.snoozeMinutes
        soundName = step.soundName ?? ""
    }

    private func applyEdits() {
        step.title = title
        step.kind = kind
        step.isEnabled = enabled

        switch kind {
        case .fixedTime:
            step.hour = hour
            step.minute = minute
            step.durationSeconds = nil
            step.offsetSeconds = nil
        case .timer:
            step.durationSeconds = minutesAmount * 60
            step.offsetSeconds = nil
            step.hour = nil
            step.minute = nil
        case .relativeToPrev:
            step.offsetSeconds = minutesAmount * 60
            step.durationSeconds = nil
            step.hour = nil
            step.minute = nil
        }

        step.allowSnooze = allowSnooze
        step.snoozeMinutes = snoozeMinutes
        step.soundName = soundName.isEmpty ? nil : soundName

        try? modelContext.save()
    }
}
