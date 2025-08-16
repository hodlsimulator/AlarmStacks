//
//  AddStackSheet.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData

struct AddStackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var addFirstStep = true
    @State private var firstStepKind: StepKind = .fixedTime
    @State private var hour: Int  = Calendar.current.component(.hour, from: Date())
    @State private var minute: Int = Calendar.current.component(.minute, from: Date())
    @State private var minutesAmount: Int = 10

    var body: some View {
        NavigationStack {
            Form {
                Section("Stack") {
                    TextField("Name", text: $name)
                }
                Section("First step") {
                    Toggle("Add a first step", isOn: $addFirstStep)
                    if addFirstStep {
                        Picker("Kind", selection: $firstStepKind) {
                            Text("Fixed time").tag(StepKind.fixedTime)
                            Text("Timer").tag(StepKind.timer)
                            Text("After previous").tag(StepKind.relativeToPrev)
                        }
                        if firstStepKind == .fixedTime {
                            Stepper(value: $hour, in: 0...23) { Text("Hour: \(hour)") }
                            Stepper(value: $minute, in: 0...59) { Text("Minute: \(minute)") }
                        } else {
                            Stepper(value: $minutesAmount, in: 1...240) { Text("\(minutesAmount) minutes") }
                        }
                    }
                }
            }
            .navigationTitle("New Stack")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createStack() }
                }
            }
        }
    }

    private func createStack() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = Stack(name: trimmed.isEmpty ? "Untitled" : trimmed)

        if addFirstStep {
            let order = 0
            let def = Settings.shared
            let step: Step
            switch firstStepKind {
            case .fixedTime:
                step = Step(title: "Wake",
                            kind: .fixedTime,
                            order: order,
                            hour: hour, minute: minute,
                            allowSnooze: def.defaultAllowSnooze,
                            snoozeMinutes: def.defaultSnoozeMinutes,
                            stack: s)
            case .timer:
                step = Step(title: "Timer",
                            kind: .timer,
                            order: order,
                            durationSeconds: minutesAmount * 60,
                            allowSnooze: def.defaultAllowSnooze,
                            snoozeMinutes: def.defaultSnoozeMinutes,
                            stack: s)
            case .relativeToPrev:
                step = Step(title: "After previous",
                            kind: .relativeToPrev,
                            order: order,
                            offsetSeconds: minutesAmount * 60,
                            allowSnooze: def.defaultAllowSnooze,
                            snoozeMinutes: def.defaultSnoozeMinutes,
                            stack: s)
            }
            s.steps = [step]
        }

        withAnimation {
            modelContext.insert(s)
        }
        try? modelContext.save()
        dismiss()
    }
}
