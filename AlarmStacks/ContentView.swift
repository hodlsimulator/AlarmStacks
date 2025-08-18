//
//  ContentView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData

// Wrapper so we can use `.sheet(item:)` later if you add export again
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Stack.createdAt, order: .reverse) private var stacks: [Stack]

    @State private var showingAddStack = false
    @State private var showingSettings = false

    // Prevent overlapping schedule/cancel on the same stack from different UI entry points
    @State private var busyStacks: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                if stacks.isEmpty {
                    EmptyState(
                        addSamples: { addSampleStacks() },
                        createNew: { showingAddStack = true }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    // Global controls
                    Section {
                        HStack {
                            Button { armAll() } label: {
                                Label("Arm All", systemImage: "bell.fill")
                            }
                            Spacer()
                            Button { disarmAll() } label: {
                                Label("Disarm All", systemImage: "bell.slash.fill")
                            }
                            .tint(.orange)
                        }
                    }

                    ForEach(stacks) { stack in
                        NavigationLink(value: stack) { StackRow(stack: stack) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { delete(stack: stack) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    withGate(for: stack) {
                                        await toggleArm(for: stack)
                                    }
                                } label: {
                                    Label(stack.isArmed ? "Disarm" : "Arm",
                                          systemImage: stack.isArmed ? "bell.slash.fill" : "bell.fill")
                                }
                                .tint(stack.isArmed ? .orange : .green)
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Alarm Stacks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddStack = true } label: {
                        Label("Add Stack", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Stack.self) { stack in
                StackDetailView(stack: stack)
            }
            // Edit a step directly (implemented in StepEditorView.swift)
            .navigationDestination(for: Step.self) { step in
                StepEditorView(step: step)
            }
        }
        .sheet(isPresented: $showingAddStack) {
            AddStackSheet { newStack in
                modelContext.insert(newStack)
                try? modelContext.save()
            }
            .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
    }

    // MARK: - Actions

    private func armAll() {
        Task { @MainActor in
            for s in stacks where !s.isArmed {
                // Gate per stack to avoid overlapping operations initiated elsewhere
                guard !busyStacks.contains(s.id) else { continue }
                busyStacks.insert(s.id)
                defer { busyStacks.remove(s.id) }

                if (try? await AlarmScheduler.shared.schedule(stack: s, calendar: .current)) != nil {
                    s.isArmed = true
                }
            }
            try? modelContext.save()
        }
    }

    private func disarmAll() {
        Task { @MainActor in
            for s in stacks where s.isArmed {
                guard !busyStacks.contains(s.id) else { continue }
                busyStacks.insert(s.id)
                defer { busyStacks.remove(s.id) }

                await AlarmScheduler.shared.cancelAll(for: s)
                s.isArmed = false
            }
            try? modelContext.save()
        }
    }

    private func toggleArm(for stack: Stack) async {
        if stack.isArmed {
            await AlarmScheduler.shared.cancelAll(for: stack)
            stack.isArmed = false
        } else {
            if (try? await AlarmScheduler.shared.schedule(stack: stack, calendar: .current)) != nil {
                stack.isArmed = true
            } else {
                stack.isArmed = false
            }
        }
        try? modelContext.save()
    }

    private func delete(stack: Stack) {
        // Ensure we cancel scheduled alarms before removing the model to avoid orphaned alerts
        Task { @MainActor in
            if !busyStacks.contains(stack.id) {
                busyStacks.insert(stack.id)
                defer { busyStacks.remove(stack.id) }
                await AlarmScheduler.shared.cancelAll(for: stack)
            }
            modelContext.delete(stack)
            try? modelContext.save()
        }
    }

    private func addSampleStacks() {
        let s1 = sampleMorning()
        let s2 = samplePomodoro()
        modelContext.insert(s1)
        modelContext.insert(s2)
        try? modelContext.save()
    }

    private func sampleMorning() -> Stack {
        let s = Stack(name: "Morning")
        let now = Date()
        let def = Settings.shared
        let wake = Step(title: "Wake", kind: .fixedTime, order: 0, createdAt: now, hour: 6, minute: 30, allowSnooze: def.defaultAllowSnooze, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        let hydrate = Step(title: "Hydrate", kind: .relativeToPrev, order: 1, createdAt: now, offsetSeconds: 10*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        let stretch = Step(title: "Stretch", kind: .timer, order: 2, createdAt: now, durationSeconds: 5*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        let shower = Step(title: "Shower", kind: .relativeToPrev, order: 3, createdAt: now, offsetSeconds: 20*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        s.steps = [wake, hydrate, stretch, shower]
        return s
    }

    private func samplePomodoro() -> Stack {
        let s = Stack(name: "Pomodoro")
        let now = Date()
        let def = Settings.shared
        s.steps = [
            Step(title: "Focus", kind: .timer, order: 0, createdAt: now, durationSeconds: 25*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s),
            Step(title: "Break", kind: .timer, order: 1, createdAt: now, durationSeconds: 5*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s),
            Step(title: "Focus", kind: .timer, order: 2, createdAt: now, durationSeconds: 25*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s),
            Step(title: "Break", kind: .timer, order: 3, createdAt: now, durationSeconds: 5*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        ]
        return s
    }

    // MARK: - Simple per-stack gate

    private func withGate(for stack: Stack, _ work: @escaping () async -> Void) {
        guard !busyStacks.contains(stack.id) else { return }
        busyStacks.insert(stack.id)
        Task { @MainActor in
            defer { busyStacks.remove(stack.id) }
            await work()
        }
    }
}

// MARK: - Row

private struct StackRow: View {
    @Bindable var stack: Stack

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(stack.name).font(.headline)
                if stack.isArmed {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .imageScale(.small)
                        .foregroundStyle(.tint)
                }
                Spacer()
                Text("\(stack.sortedSteps.count) step\(stack.sortedSteps.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stack.sortedSteps) { step in
                        // Tap to edit a step
                        NavigationLink(value: step) {
                            StepChip(step: step)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct StepChip: View {
    let step: Step

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: step)).imageScale(.small)
            Text(label(for: step)).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private func icon(for step: Step) -> String {
        switch step.kind {
        case .fixedTime: return "alarm"
        case .timer: return "timer"
        case .relativeToPrev: return "plus.circle"
        }
    }

    private func label(for step: Step) -> String {
        switch step.kind {
        case .fixedTime:
            var time = "Time"
            if let h = step.hour, let m = step.minute { time = String(format: "%02d:%02d", h, m) }
            let days = daysText(for: step)
            if days.isEmpty { return "\(time)  \(step.title)" }
            return "\(time) • \(days)  \(step.title)"
        case .timer:
            if let s = step.durationSeconds { return "\(format(seconds: s))  \(step.title)" }
            return step.title
        case .relativeToPrev:
            if let s = step.offsetSeconds {
                let sign = s >= 0 ? "+" : "−"
                return "\(sign)\(format(seconds: abs(s)))  \(step.title)"
            }
            return step.title
        }
    }

    private func format(seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    private func daysText(for step: Step) -> String {
        let map = [2:"Mon",3:"Tue",4:"Wed",5:"Thu",6:"Fri",7:"Sat",1:"Sun"]
        let chosen: [Int]
        if let arr = step.weekdays, !arr.isEmpty {
            chosen = arr
        } else if let one = step.weekday {
            chosen = [one]
        } else {
            return ""
        }
        let set = Set(chosen)
        if set.count == 7 { return "Every day" }
        if set == Set([2,3,4,5,6]) { return "Weekdays" }
        if set == Set([1,7]) { return "Weekend" }
        let order = [2,3,4,5,6,7,1]
        return order.filter { set.contains($0) }.compactMap { map[$0] }.joined(separator: " ")
    }
}

// MARK: - Detail

private struct StackDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var calendar = Calendar.current
    @State private var showingAddSheet = false

    // Local busy flag to avoid overlapping cancel/reschedule from detail screen
    @State private var isBusy = false

    @Bindable var stack: Stack

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { stack.isArmed }, set: { newVal in
                    guard !isBusy else { return }
                    isBusy = true
                    Task { @MainActor in
                        if newVal {
                            if (try? await AlarmScheduler.shared.schedule(stack: stack, calendar: calendar)) != nil {
                                stack.isArmed = true
                            }
                        } else {
                            await AlarmScheduler.shared.cancelAll(for: stack)
                            stack.isArmed = false
                        }
                        try? modelContext.save()
                        isBusy = false
                    }
                })) { Text("Armed") }
            }

            Section("Steps") {
                ForEach(stack.sortedSteps) { step in
                    NavigationLink(value: step) { StepRow(step: step) }
                }
                .onDelete { idx in
                    let snapshot = stack.sortedSteps
                    for i in idx { modelContext.delete(snapshot[i]) }
                    try? modelContext.save()

                    // Auto-reschedule after deletion (guard against overlap)
                    if stack.isArmed, !isBusy {
                        isBusy = true
                        Task { @MainActor in
                            await AlarmScheduler.shared.cancelAll(for: stack)
                            _ = try? await AlarmScheduler.shared.schedule(stack: stack, calendar: calendar)
                            isBusy = false
                        }
                    }
                }
            }
        }
        .navigationTitle(stack.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddSheet = true } label: {
                    Label("Add Step", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddStepSheet(stack: stack)
                .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
    }
}

private struct StepRow: View {
    @Bindable var step: Step
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(step.title).font(.headline)
                Text(detailText(for: step)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: step.isEnabled ? "checkmark.circle.fill" : "xmark.circle")
        }
    }
    private func detailText(for: Step) -> String {
        switch step.kind {
        case .fixedTime:
            var time = "Fixed"
            if let h = step.hour, let m = step.minute { time = String(format: "Fixed • %02d:%02d", h, m) }
            let days = daysText(for: step)
            return days.isEmpty ? time : "\(time) • \(days)"
        case .timer:
            if let s = step.durationSeconds { return "Timer • \(format(seconds: s))" }
            return "Timer"
        case .relativeToPrev:
            if let s = step.offsetSeconds {
                if s >= 0 {
                    return "After previous • +\(format(seconds: s))"
                } else {
                    return "Before previous • −\(format(seconds: -s))"
                }
            }
            return "After previous"
        }
    }
    private func format(seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
    private func daysText(for step: Step) -> String {
        let map = [2:"Mon",3:"Tue",4:"Wed",5:"Thu",6:"Fri",7:"Sat",1:"Sun"]
        let chosen: [Int]
        if let arr = step.weekdays, !arr.isEmpty {
            chosen = arr
        } else if let one = step.weekday {
            chosen = [one]
        } else {
            return ""
        }
        let set = Set(chosen)
        if set.count == 7 { return "Every day" }
        if set == Set([2,3,4,5,6]) { return "Weekdays" }
        if set == Set([1,7]) { return "Weekend" }
        let order = [2,3,4,5,6,7,1]
        return order.filter { set.contains($0) }.compactMap { map[$0] }.joined(separator: " ")
    }
}

// MARK: - Add Stack / Step

private struct AddStackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    var onCreate: (Stack) -> Void

    @State private var addFirstStep = true
    @State private var firstStepKind: StepKind = .fixedTime

    // Unified time-of-day picker
    @State private var firstStepTime: Date = Date()

    // Duration / After previous (shared UI style)
    @State private var direction: Direction = .after
    @State private var minutesAmount: Int = 10
    @State private var secondsAmount: Int = 0

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
                        .pickerStyle(.segmented)

                        switch firstStepKind {
                        case .fixedTime:
                            DatePicker("Time", selection: $firstStepTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)

                        case .timer:
                            durationEditors

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
                        }
                    }
                }
            }
            .navigationTitle("New Stack")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let s = Stack(name: trimmed.isEmpty ? "Untitled" : trimmed)

                        if addFirstStep {
                            let def = Settings.shared
                            let order = 0
                            let step: Step
                            switch firstStepKind {
                            case .fixedTime:
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: firstStepTime)
                                step = Step(title: "Wake",
                                            kind: .fixedTime,
                                            order: order,
                                            hour: comps.hour, minute: comps.minute,
                                            allowSnooze: def.defaultAllowSnooze,
                                            snoozeMinutes: def.defaultSnoozeMinutes,
                                            stack: s)
                            case .timer:
                                let secs = max(1, totalSeconds)
                                step = Step(title: "Timer",
                                            kind: .timer,
                                            order: order,
                                            durationSeconds: secs,
                                            allowSnooze: def.defaultAllowSnooze,
                                            snoozeMinutes: def.defaultSnoozeMinutes,
                                            stack: s)
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
                    .disabled(addFirstStep && (firstStepKind != .fixedTime && totalSeconds == 0))
                }
            }
        }
    }

    // MARK: - Subviews (shared with AddStepSheet below)

    private var durationEditors: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Duration") {
                Text(formatted(totalSeconds))
                    .monospacedDigit()
            }
            HStack {
                Stepper(value: $minutesAmount, in: 0...720) {
                    Text("Minutes: \(minutesAmount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Stepper(value: $secondsAmount, in: 0...59) {
                    Text("Seconds: \(secondsAmount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .labelStyle(.titleOnly)
        }
    }

    // MARK: - Helpers

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

    // MARK: - Types

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

private struct AddStepSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let stack: Stack

    @State private var title: String = ""
    @State private var kind: StepKind = .fixedTime

    // Fixed time (unified DatePicker)
    @State private var timeOfDay: Date = Date()

    // Duration / After previous
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
                        Text("Timer").tag(StepKind.timer)
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
                    Section("Duration") {
                        durationEditors
                    }
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
                    }
                }
            }
            .navigationTitle("Add Step")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addStep()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || invalidDuration)
                }
            }
        }
    }

    // MARK: - Subviews

    private var durationEditors: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Duration") {
                Text(formatted(totalSeconds))
                    .monospacedDigit()
            }
            HStack {
                Stepper(value: $minutesAmount, in: 0...720) {
                    Text("Minutes: \(minutesAmount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Stepper(value: $secondsAmount, in: 0...59) {
                    Text("Seconds: \(secondsAmount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .labelStyle(.titleOnly)
        }
    }

    // MARK: - Helpers

    private var totalSeconds: Int {
        max(0, minutesAmount) * 60 + max(0, min(59, secondsAmount))
    }

    private var invalidDuration: Bool {
        if kind == .timer || kind == .relativeToPrev {
            return totalSeconds == 0
        }
        return false
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
        let order = (stack.sortedSteps.last?.order ?? -1) + 1
        let def = Settings.shared
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = trimmed.isEmpty ? (kind == .fixedTime ? "Alarm" : (kind == .timer ? "Timer" : "After previous")) : trimmed

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
            let secs = max(1, totalSeconds)
            step = Step(title: safeTitle,
                        kind: .timer,
                        order: order,
                        durationSeconds: secs,
                        allowSnooze: def.defaultAllowSnooze,
                        snoozeMinutes: def.defaultSnoozeMinutes,
                        stack: stack)

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

        // Auto-reschedule when adding a step
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

    // MARK: - Types

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

// MARK: - Empty State

private struct EmptyState: View {
    var addSamples: () -> Void
    var createNew: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "alarm.fill").font(.largeTitle)
            Text("No stacks yet").font(.headline)
            Text("Create a stack or add sample ones to get started.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Add Sample Stacks", action: addSamples)
                Button("Create New", action: createNew)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
}
