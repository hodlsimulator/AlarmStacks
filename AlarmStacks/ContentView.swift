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

    var body: some View {
        NavigationStack {
            List {
                if stacks.isEmpty {
                    EmptyState(addAction: addSampleStacks)
                        .listRowBackground(Color.clear)
                } else {
                    // Global controls (safe, no scene watchers)
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
                                Button { Task { await toggleArm(for: stack) } } label: {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddStack = true } label: {
                        Label("Add Stack", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Stack.self) { stack in
                StackDetailView(stack: stack)
            }
            // Edit a step
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
    }

    // MARK: - Actions

    private func armAll() {
        Task { @MainActor in
            for s in stacks where !s.isArmed {
                _ = try? await AlarmScheduler.shared.schedule(stack: s, calendar: .current)
                s.isArmed = true
            }
            try? modelContext.save()
        }
    }

    private func disarmAll() {
        Task { @MainActor in
            for s in stacks where s.isArmed {
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
            do {
                _ = try await AlarmScheduler.shared.schedule(stack: stack, calendar: .current)
                stack.isArmed = true
            } catch {
                stack.isArmed = false
            }
        }
        try? modelContext.save()
    }

    private func delete(stack: Stack) {
        modelContext.delete(stack)
        try? modelContext.save()
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
        let wake = Step(title: "Wake", kind: .fixedTime, order: 0, createdAt: now, hour: 6, minute: 30, stack: s)
        let hydrate = Step(title: "Hydrate", kind: .relativeToPrev, order: 1, createdAt: now, offsetSeconds: 10*60, allowSnooze: false, snoozeMinutes: 5, stack: s)
        let stretch = Step(title: "Stretch", kind: .timer, order: 2, createdAt: now, durationSeconds: 5*60, allowSnooze: false, snoozeMinutes: 5, stack: s)
        let shower = Step(title: "Shower", kind: .relativeToPrev, order: 3, createdAt: now, offsetSeconds: 20*60, allowSnooze: false, snoozeMinutes: 5, stack: s)
        s.steps = [wake, hydrate, stretch, shower]
        return s
    }

    private func samplePomodoro() -> Stack {
        let s = Stack(name: "Pomodoro")
        let now = Date()
        s.steps = [
            Step(title: "Focus", kind: .timer, order: 0, createdAt: now, durationSeconds: 25*60, allowSnooze: false, stack: s),
            Step(title: "Break", kind: .timer, order: 1, createdAt: now, durationSeconds: 5*60, allowSnooze: false, stack: s),
            Step(title: "Focus", kind: .timer, order: 2, createdAt: now, durationSeconds: 25*60, allowSnooze: false, stack: s),
            Step(title: "Break", kind: .timer, order: 3, createdAt: now, durationSeconds: 5*60, allowSnooze: false, stack: s)
        ]
        return s
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
                        // Tap a chip to edit that step
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
            Image(systemName: icon(for: step))
                .imageScale(.small)
            Text(label(for: step))
                .font(.caption)
                .lineLimit(1)
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
            if let s = step.offsetSeconds { return "+\(format(seconds: s))  \(step.title)" }
            return step.title
        }
    }

    private func format(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(seconds % 60)s"
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

    @Bindable var stack: Stack

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { stack.isArmed }, set: { newVal in
                    Task {
                        if newVal {
                            _ = try? await AlarmScheduler.shared.schedule(stack: stack, calendar: calendar)
                        } else {
                            await AlarmScheduler.shared.cancelAll(for: stack)
                        }
                        stack.isArmed = newVal
                        try? modelContext.save()
                    }
                })) { Text("Armed") }
            }

            Section("Steps") {
                ForEach(stack.sortedSteps) { step in
                    NavigationLink(value: step) {
                        StepRow(step: step)
                    }
                }
                .onDelete { idx in
                    let snapshot = stack.sortedSteps
                    for i in idx { modelContext.delete(snapshot[i]) }
                    try? modelContext.save()
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
                Text(detailText(for: step))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: step.isEnabled ? "checkmark.circle.fill" : "xmark.circle")
        }
    }

    private func detailText(for step: Step) -> String {
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
            if let s = step.offsetSeconds { return "After previous • +\(format(seconds: s))" }
            return "After previous"
        }
    }

    private func format(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
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
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let s = Stack(name: trimmed.isEmpty ? "Untitled" : trimmed)
                        if addFirstStep {
                            let order = 0
                            let step: Step
                            switch firstStepKind {
                            case .fixedTime:
                                step = Step(title: "Wake",
                                            kind: .fixedTime,
                                            order: order,
                                            hour: hour, minute: minute,
                                            stack: s)
                            case .timer:
                                step = Step(title: "Timer",
                                            kind: .timer,
                                            order: order,
                                            durationSeconds: minutesAmount * 60,
                                            stack: s)
                            case .relativeToPrev:
                                step = Step(title: "After previous",
                                            kind: .relativeToPrev,
                                            order: order,
                                            offsetSeconds: minutesAmount * 60,
                                            stack: s)
                            }
                            s.steps = [step]
                        }
                        onCreate(s)
                        dismiss()
                    }
                    // NOTE: do NOT disable when name is empty → we default to "Untitled"
                }
            }
        }
    }
}

private struct AddStepSheet: View {
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
                    Button("Add") {
                        addStep()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func addStep() {
        let order = (stack.sortedSteps.last?.order ?? -1) + 1
        let step: Step
        switch kind {
        case .fixedTime:
            step = Step(title: title,
                        kind: .fixedTime,
                        order: order,
                        hour: hour,
                        minute: minute,
                        stack: stack)
        case .timer:
            step = Step(title: title,
                        kind: .timer,
                        order: order,
                        durationSeconds: minutesAmount * 60,
                        stack: stack)
        case .relativeToPrev:
            step = Step(title: title,
                        kind: .relativeToPrev,
                        order: order,
                        offsetSeconds: minutesAmount * 60,
                        stack: stack)
        }
        stack.steps.append(step)
        try? modelContext.save()
    }
}

// MARK: - Empty State

private struct EmptyState: View {
    var addAction: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "alarm.fill").font(.largeTitle)
            Text("No stacks yet").font(.headline)
            Text("Create a stack or add sample ones to get started.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Add Sample Stacks", action: addAction)
                Button("Create New") { /* handled by + button in toolbar */ }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
}
