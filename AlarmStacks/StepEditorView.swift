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

    // Weekday multi-select for fixed-time (1...7, Sun=1)
    @State private var weekdaySelection: Set<Int> = []
    // Timer cadence
    @State private var everyNDaysEnabled: Bool = false
    @State private var everyNDays: Int = 1

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

                Section("Repeat on") {
                    WeekdayPicker(selection: $weekdaySelection)
                        .accessibilityHint("Select the weekdays this step should run on. Leave all off to allow any day.")
                    if !weekdaySelection.isEmpty {
                        Text("Selected: \(formatSelectedDays(weekdaySelection))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No days selected → runs on the next day at the chosen time.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if kind == .timer {
                Section("Duration") {
                    Stepper(value: $minutesAmount, in: 1...240) { Text("\(minutesAmount) minutes") }
                }
                Section("Cadence") {
                    Toggle("Repeat every N days", isOn: $everyNDaysEnabled.animation())
                    if everyNDaysEnabled {
                        Stepper(value: $everyNDays, in: 1...30) {
                            Text(everyNDays == 1 ? "Every day" : "Every \(everyNDays) days")
                        }
                    } else {
                        Text("Off → timer fires based on sequence timing only.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Offset") {
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

        if let multi = step.weekdays, !multi.isEmpty {
            weekdaySelection = Set(multi)
        } else if let one = step.weekday {
            weekdaySelection = [one]
        } else {
            weekdaySelection = []
        }

        if let n = step.everyNDays, n >= 1 {
            everyNDaysEnabled = true
            everyNDays = n
        } else {
            everyNDaysEnabled = false
            everyNDays = 1
        }
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

            let sortedDays = weekdaySelection.sorted()
            step.weekdays = sortedDays.isEmpty ? nil : sortedDays
            step.weekday = sortedDays.count == 1 ? sortedDays.first : nil
            step.everyNDays = nil

        case .timer:
            step.durationSeconds = minutesAmount * 60
            step.offsetSeconds = nil
            step.hour = nil
            step.minute = nil
            step.everyNDays = everyNDaysEnabled ? max(1, everyNDays) : nil
            step.weekdays = nil
            step.weekday = nil

        case .relativeToPrev:
            step.offsetSeconds = minutesAmount * 60
            step.durationSeconds = nil
            step.hour = nil
            step.minute = nil
            step.weekdays = nil
            step.weekday = nil
            step.everyNDays = nil
        }

        step.allowSnooze = allowSnooze
        step.snoozeMinutes = snoozeMinutes
        step.soundName = soundName.isEmpty ? nil : soundName

        try? modelContext.save()
    }

    private func formatSelectedDays(_ set: Set<Int>) -> String {
        let order = [2,3,4,5,6,7,1] // Mon..Sun
        let map = [1:"Sun",2:"Mon",3:"Tue",4:"Wed",5:"Thu",6:"Fri",7:"Sat"]
        let picked = order.filter { set.contains($0) }.compactMap { map[$0] }
        return picked.joined(separator: " ")
    }
}

// MARK: - WeekdayPicker (no ForEach; no mixed ShapeStyles)

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int> // 1...7 (Sun=1)

    private func chip(_ id: Int, _ title: String) -> some View {
        let isOn = selection.contains(id)
        return Button {
            if isOn { selection.remove(id) } else { selection.insert(id) }
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    if isOn {
                        Capsule().fill(Color.accentColor.opacity(0.2))
                    } else {
                        Capsule().fill(.thinMaterial)
                    }
                }
                .overlay(
                    Capsule().stroke(isOn ? Color.accentColor : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 8) {
            chip(2, "Mon")
            chip(3, "Tue")
            chip(4, "Wed")
            chip(5, "Thu")
            chip(6, "Fri")
            chip(7, "Sat")
            chip(1, "Sun")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
