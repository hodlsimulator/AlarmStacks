//
//  AddStackStepSheets.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import SwiftData

// MARK: - Add Stack

struct AddStackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    var onCreate: (Stack) -> Void

    @State private var addFirstStep = true
    @State private var firstStepKind: StepKind = .fixedTime

    // Unified time-of-day picker
    @State private var firstStepTime: Date = Date()

    // After previous (shared UI style)
    @State private var direction: Direction = .after
    @State private var minutesAmount: Int = 10
    @State private var secondsAmount: Int = 0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section("Stack") {
                        TextField("Name", text: $name)
                    }

                    Section("First step") {
                        Toggle("Add a first step", isOn: $addFirstStep)

                        if addFirstStep {
                            Picker("Kind", selection: $firstStepKind) {
                                Text("Fixed time").tag(StepKind.fixedTime)
                                Text("After previous").tag(StepKind.relativeToPrev)
                            }
                            .pickerStyle(.segmented)

                            switch firstStepKind {
                            case .fixedTime:
                                DatePicker("Time",
                                           selection: $firstStepTime,
                                           displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .id("firstStepWheel")

                            case .timer:
                                EmptyView() // no longer offered

                            case .relativeToPrev:
                                Picker("Direction", selection: $direction) {
                                    Text("After").tag(Direction.after)
                                    Text("Before").tag(Direction.before)
                                }
                                .pickerStyle(.segmented)

                                durationEditors

                                Text(humanReadableRelative)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                                    .singleLineTightTail()
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .dismissKeyboardOnTapAnywhere()
                .scrollContentBackground(.hidden)
                .background(.clear)
                .contentMargins(.bottom, 36, for: .scrollContent)
                .onAppear {
                    if addFirstStep && firstStepKind == .fixedTime {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 60_000_000)
                            withAnimation(.snappy) { proxy.scrollTo("firstStepWheel", anchor: .bottom) }
                        }
                    }
                }
                .onChange(of: firstStepKind) { _, new in
                    if addFirstStep && new == .fixedTime {
                        withAnimation(.snappy) { proxy.scrollTo("firstStepWheel", anchor: .bottom) }
                    }
                }
            }
            .navigationTitle("New Stack")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                    .disabled(addFirstStep && firstStepKind == .relativeToPrev && totalSeconds == 0)
                }
            }
        }
    }

    private var durationEditors: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Delay") {
                Text(formatted(totalSeconds)).monospacedDigit().singleLineTightTail()
            }
            HStack {
                Stepper(value: $minutesAmount, in: 0...720) {
                    Text("Minutes: \(minutesAmount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .singleLineTightTail()
                }
                Stepper(value: $secondsAmount, in: 0...59) {
                    Text("Seconds: \(secondsAmount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .singleLineTightTail()
                }
            }
            .labelStyle(.titleOnly)
        }
    }

    private var totalSeconds: Int {
        max(0, minutesAmount) * 60 + max(0, min(59, secondsAmount))
    }

    private var humanReadableRelative: String {
        let s = totalSeconds
        guard s > 0 else { return "No delay" }
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        let dur: String = {
            if h > 0 { return "\(h)h \(m)m" }
            if m > 0 && sec > 0 { return "\(m)m \(sec)s" }
            if m > 0 { return "\(m)m" }
            return "\(sec)s"
        }()
        return direction == .after ? "\(dur) after previous" : "\(dur) before previous"
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = Stack(name: trimmed.isEmpty ? "Untitled" : trimmed)

        if addFirstStep {
            let def = Settings.shared
            let order = 0
            let step: Step
            switch firstStepKind {
            case .fixedTime:
                let c = Calendar.current.dateComponents([.hour, .minute], from: firstStepTime)
                step = Step(title: "Start",
                            kind: .fixedTime,
                            order: order,
                            hour: c.hour, minute: c.minute,
                            allowSnooze: def.defaultAllowSnooze,
                            snoozeMinutes: def.defaultSnoozeMinutes,
                            stack: s)
            case .timer:
                fatalError("Timer is no longer available for creation.")
            case .relativeToPrev:
                let secs = max(0, totalSeconds)
                let signed = (direction == .after ? 1 : -1) * secs
                step = Step(title: "After previous",
                            kind: .relativeToPrev,
                            order: order,
                            offsetSeconds: signed,
                            allowSnooze: def.defaultAllowSnooze,
                            snoozeMinutes: def.defaultSnoozeMinutes,
                            stack: s)
            }
            s.steps = [step]
        }

        onCreate(s)
        dismiss()
    }

    private enum Direction { case after, before }

    private func formatted(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }
}

// MARK: - Add Step

struct AddStepSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: ModalRouter
    @StateObject private var store = Store.shared

    let stack: Stack

    @State private var title: String = ""
    @State private var kind: StepKind = .fixedTime

    // Fixed time (unified DatePicker)
    @State private var timeOfDay: Date = Date()

    // After previous
    @State private var direction: Direction = .after
    @State private var minutesAmount: Int = 10
    @State private var secondsAmount: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                    Picker("Kind", selection: $kind) {
                        Text("Fixed time").tag(StepKind.fixedTime)
                        Text("After previous").tag(StepKind.relativeToPrev)
                    }
                    .pickerStyle(.segmented)
                }

                switch kind {
                case .fixedTime:
                    Section("Time") {
                        DatePicker("Time", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                    }
                case .timer:
                    EmptyView() // kept for exhaustiveness
                case .relativeToPrev:
                    Section("After previous") {
                        Picker("Direction", selection: $direction) {
                            Text("After").tag(Direction.after)
                            Text("Before").tag(Direction.before)
                        }
                        .pickerStyle(.segmented)

                        durationEditors

                        Text(humanReadableRelative)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                            .singleLineTightTail()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTapAnywhere()
            .scrollContentBackground(.hidden)
            .background(.clear)

            .navigationTitle("Add Step")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        // UI-level guard: if cap hit, dismiss this sheet and show Paywall on top.
                        if !store.isPlus && stack.steps.count >= FreeTier.stepsPerStackLimit {
                            dismiss()
                            Task { @MainActor in
                                // brief delay so the add sheet closes before we present Paywall
                                try? await Task.sleep(nanoseconds: 150_000_000)
                                router.showPaywall(trigger: .steps)
                            }
                        } else {
                            addStep()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || invalidDuration)
                }
            }
        }
        // If user got here via a stale entry point, redirect immediately.
        .task { @MainActor in
            if !store.isPlus && stack.steps.count >= FreeTier.stepsPerStackLimit {
                dismiss()
                try? await Task.sleep(nanoseconds: 150_000_000)
                router.showPaywall(trigger: .steps)
            }
        }
    }

    private var durationEditors: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Delay") {
                Text(formatted(totalSeconds))
                    .monospacedDigit()
                    .singleLineTightTail()
            }
            HStack {
                Stepper(value: $minutesAmount, in: 0...720) {
                    Text("Minutes: \(minutesAmount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .singleLineTightTail()
                }
                Stepper(value: $secondsAmount, in: 0...59) {
                    Text("Seconds: \(secondsAmount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .singleLineTightTail()
                }
            }
            .labelStyle(.titleOnly)
        }
    }

    private var totalSeconds: Int {
        max(0, minutesAmount) * 60 + max(0, min(59, secondsAmount))
    }

    private var invalidDuration: Bool {
        (kind == .relativeToPrev) && totalSeconds == 0
    }

    private var humanReadableRelative: String {
        let s = totalSeconds
        guard s > 0 else { return "No delay" }
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        let dur: String = {
            if h > 0 { return "\(h)h \(m)m" }
            if m > 0 && sec > 0 { return "\(m)m \(sec)s" }
            if m > 0 { return "\(m)m" }
            return "\(sec)s"
        }()
        return direction == .after ? "\(dur) after previous" : "\(dur) before previous"
    }

    private func addStep() {
        // Model-level guard (belt-and-braces)
        if !store.isPlus && stack.steps.count >= FreeTier.stepsPerStackLimit {
            // If somehow reached here, dismiss first then show Paywall
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                router.showPaywall(trigger: .steps)
            }
            return
        }

        let order = (stack.sortedSteps.last?.order ?? -1) + 1
        let def = Settings.shared
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = trimmed.isEmpty ? (kind == .fixedTime ? "Start" : "After previous") : trimmed

        let step: Step
        switch kind {
        case .fixedTime:
            let comps = Calendar.current.dateComponents([.hour, .minute], from: timeOfDay)
            step = Step(title: safeTitle,
                        kind: .fixedTime,
                        order: order,
                        hour: comps.hour,
                        minute: comps.minute,
                        allowSnooze: def.defaultAllowSnooze,
                        snoozeMinutes: def.defaultSnoozeMinutes,
                        stack: stack)

        case .timer:
            fatalError("Timer is no longer available for creation.")

        case .relativeToPrev:
            let secs = max(0, totalSeconds)
            let signed = (direction == .after ? 1 : -1) * secs
            step = Step(title: safeTitle,
                        kind: .relativeToPrev,
                        order: order,
                        offsetSeconds: signed,
                        allowSnooze: def.defaultAllowSnooze,
                        snoozeMinutes: def.defaultSnoozeMinutes,
                        stack: stack)
        }

        stack.steps.append(step)
        try? modelContext.save()

        if stack.isArmed {
            Task { @MainActor in
                await AlarmScheduler.shared.cancelAll(for: stack)
                _ = try? await AlarmScheduler.shared.schedule(stack: stack, calendar: .current)
                dismiss()
            }
        } else {
            dismiss()
        }
    }

    private enum Direction { case after, before }

    private func formatted(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }
}
