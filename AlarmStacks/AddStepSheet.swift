//
//  AddStepSheet.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData

struct AddStepSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let stack: Stack

    @State private var title: String = ""
    @State private var kind: StepKind = .fixedTime
    @State private var hour: Int  = Calendar.current.component(.hour, from: Date())
    @State private var minute: Int = Calendar.current.component(.minute, from: Date())
    @State private var minutesAmount: Int = 10

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $title)
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
            }
            .navigationTitle("Add Step")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addStep() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func addStep() {
        let order = (stack.sortedSteps.last?.order ?? -1) + 1
        let def = Settings.shared
        let step: Step
        switch kind {
        case .fixedTime:
            step = Step(title: title,
                        kind: .fixedTime,
                        order: order,
                        hour: hour,
                        minute: minute,
                        allowSnooze: def.defaultAllowSnooze,
                        snoozeMinutes: def.defaultSnoozeMinutes,
                        stack: stack)
        case .timer:
            step = Step(title: title,
                        kind: .timer,
                        order: order,
                        durationSeconds: minutesAmount * 60,
                        allowSnooze: def.defaultAllowSnooze,
                        snoozeMinutes: def.defaultSnoozeMinutes,
                        stack: stack)
        case .relativeToPrev:
            step = Step(title: title,
                        kind: .relativeToPrev,
                        order: order,
                        offsetSeconds: minutesAmount * 60,
                        allowSnooze: def.defaultAllowSnooze,
                        snoozeMinutes: def.defaultSnoozeMinutes,
                        stack: stack)
        }
        withAnimation {
            stack.steps.append(step)
        }
        try? modelContext.save()
        dismiss()
    }
}
