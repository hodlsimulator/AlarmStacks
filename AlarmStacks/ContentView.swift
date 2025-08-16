//
//  ContentView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData

// Wrapper so we can use `.sheet(item:)` for export
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Stack.createdAt, order: .reverse) private var stacks: [Stack]

    @State private var showingAddStack = false
    @State private var showingSettings = false
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            Group {
                if stacks.isEmpty {
                    // Full-screen onboarding when empty (not inside a List row)
                    ScrollView {
                        EmptyState(
                            addSamples: { addSampleStacks() },
                            createNew: { showingAddStack = true }
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .padding(.top, 40)
                    }
                } else {
                    List {
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
                                // ← Swipe left to delete
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(stack: stack)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red) // make Delete red
                                }
                                .contextMenu {
                                    Button { toggleArm(for: stack) } label: {
                                        Label(stack.isArmed ? "Disarm" : "Arm",
                                              systemImage: stack.isArmed ? "bell.slash.fill" : "bell.fill")
                                    }
                                    Button { duplicate(stack: stack) } label: {
                                        Label("Duplicate", systemImage: "plus.square.on.square")
                                    }
                                    Button {
                                        do { shareItem = try ShareItem(url: writeExportFile(for: stack)) } catch { shareItem = nil }
                                    } label: {
                                        Label("Export…", systemImage: "square.and.arrow.up")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Alarm Stacks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gear")
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
            // Also support navigating straight to editing a Step
            .navigationDestination(for: Step.self) { step in
                StepEditorView(step: step)
            }
        }
        // Re-check permissions and reschedule when returning from Settings
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    _ = try? await AlarmScheduler.shared.requestAuthorizationIfNeeded()
                    await AlarmScheduler.shared.rescheduleAll(stacks: stacks.filter { $0.isArmed }, calendar: .current)
                }
            }
        }
        // Also reschedule on significant time changes (DST, timezone, clock)
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIApplication.significantTimeChangeNotification) {
                await AlarmScheduler.shared.rescheduleAll(stacks: stacks.filter { $0.isArmed }, calendar: .current)
            }
        }
        // Sheets (Add stack / Settings provided elsewhere), Export share sheet:
        .sheet(item: $shareItem) { item in
            ShareView(url: item.url)
        }
        .sheet(isPresented: $showingAddStack) {
            // Insert/sync happens *inside* AddStackSheet via its modelContext
            AddStackSheet()
                .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
    }

    // MARK: - Sync wrappers that spawn Tasks

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

    private func toggleArm(for stack: Stack) {
        Task { @MainActor in
            if stack.isArmed {
                await AlarmScheduler.shared.cancelAll(for: stack)
                stack.isArmed = false
            } else {
                _ = try? await AlarmScheduler.shared.schedule(stack: stack, calendar: .current)
                stack.isArmed = true
            }
            try? modelContext.save()
        }
    }

    private func duplicate(stack: Stack) {
        let copy = Stack(name: stack.name + " (Copy)",
                         isArmed: false,
                         createdAt: .now,
                         themeName: stack.themeName)
        copy.steps = stack.sortedSteps.map { s in
            Step(title: s.title,
                 kind: s.kind,
                 order: s.order,
                 isEnabled: s.isEnabled,
                 createdAt: .now,
                 hour: s.hour,
                 minute: s.minute,
                 weekday: s.weekday,
                 weekdays: s.weekdays,
                 durationSeconds: s.durationSeconds,
                 offsetSeconds: s.offsetSeconds,
                 soundName: s.soundName,
                 allowSnooze: s.allowSnooze,
                 snoozeMinutes: s.snoozeMinutes,
                 everyNDays: s.everyNDays,
                 stack: copy)
        }
        withAnimation {
            modelContext.insert(copy)
        }
        try? modelContext.save()
    }

    private func delete(stack: Stack) {
        withAnimation {
            modelContext.delete(stack)
        }
        try? modelContext.save()
    }

    @MainActor
    private func addSampleStacks() {
        let s1 = sampleMorning()
        let s2 = samplePomodoro()
        withAnimation {
            modelContext.insert(s1)
            modelContext.insert(s2)
        }
        try? modelContext.save()
    }

    // MARK: - Sample builders

    @MainActor
    private func sampleMorning() -> Stack {
        let s = Stack(name: "Morning")
        let now = Date()
        let settings = Settings.shared
        let wake = Step(title: "Wake", kind: .fixedTime, order: 0, createdAt: now, hour: 6, minute: 30, allowSnooze: settings.defaultAllowSnooze, snoozeMinutes: settings.defaultSnoozeMinutes, stack: s)
        // Example: Weekdays for Wake
        wake.weekdays = [2,3,4,5,6]
        let hydrate = Step(title: "Hydrate", kind: .relativeToPrev, order: 1, createdAt: now, offsetSeconds: 10*60, allowSnooze: false, snoozeMinutes: settings.defaultSnoozeMinutes, stack: s)
        let stretch = Step(title: "Stretch", kind: .timer, order: 2, createdAt: now, durationSeconds: 5*60, allowSnooze: false, snoozeMinutes: settings.defaultSnoozeMinutes, stack: s)
        let shower = Step(title: "Shower", kind: .relativeToPrev, order: 3, createdAt: now, offsetSeconds: 20*60, allowSnooze: false, snoozeMinutes: settings.defaultSnoozeMinutes, stack: s)
        s.steps = [wake, hydrate, stretch, shower]
        return s
    }

    @MainActor
    private func samplePomodoro() -> Stack {
        let s = Stack(name: "Pomodoro")
        let now = Date()
        let settings = Settings.shared
        s.steps = [
            Step(title: "Focus", kind: .timer, order: 0, createdAt: now, durationSeconds: 25*60, allowSnooze: false, snoozeMinutes: settings.defaultSnoozeMinutes, stack: s),
            Step(title: "Break", kind: .timer, order: 1, createdAt: now, durationSeconds: 5*60, allowSnooze: false, snoozeMinutes: settings.defaultSnoozeMinutes, stack: s),
            Step(title: "Focus", kind: .timer, order: 2, createdAt: now, durationSeconds: 25*60, allowSnooze: false, snoozeMinutes: settings.defaultSnoozeMinutes, stack: s),
            Step(title: "Break", kind: .timer, order: 3, createdAt: now, durationSeconds: 5*60, allowSnooze: false, snoozeMinutes: settings.defaultSnoozeMinutes, stack: s)
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
                        // Tapping a chip opens the editor via navigationDestination(for: Step.self)
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
            if let s = step.offsetSeconds { return "+\(format(seconds: s))  \(step.title)" }
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
    @State private var shareItem: ShareItem?

    @Bindable var stack: Stack

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { stack.isArmed }, set: { newVal in
                    Task { @MainActor in
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
                    // Tap to edit a step
                    NavigationLink(value: step) {
                        StepRow(step: step)
                    }
                }
                .onDelete { idx in
                    let snapshot = stack.sortedSteps
                    withAnimation {
                        for i in idx { modelContext.delete(snapshot[i]) }
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle(stack.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        let _ = duplicate()
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }

                    Button {
                        do { shareItem = try ShareItem(url: writeExportFile(for: stack)) } catch { shareItem = nil }
                    } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        withAnimation {
                            modelContext.delete(stack)
                            try? modelContext.save()
                        }
                    } label: {
                        Label("Delete Stack", systemImage: "trash")
                    }
                    .tint(.red) // ensure Delete is red
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }

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
        .sheet(item: $shareItem) { item in
            ShareView(url: item.url)
        }
    }

    private func duplicate() -> Stack {
        let copy = Stack(name: stack.name + " (Copy)",
                         isArmed: false,
                         createdAt: .now,
                         themeName: stack.themeName)
        copy.steps = stack.sortedSteps.map { s in
            Step(title: s.title,
                 kind: s.kind,
                 order: s.order,
                 isEnabled: s.isEnabled,
                 createdAt: .now,
                 hour: s.hour,
                 minute: s.minute,
                 weekday: s.weekday,
                 weekdays: s.weekdays,
                 durationSeconds: s.durationSeconds,
                 offsetSeconds: s.offsetSeconds,
                 soundName: s.soundName,
                 allowSnooze: s.allowSnooze,
                 snoozeMinutes: s.snoozeMinutes,
                 everyNDays: s.everyNDays,
                 stack: copy)
        }
        withAnimation {
            modelContext.insert(copy)
            try? modelContext.save()
        }
        return copy
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
    private func detailText(for step: Step) -> String {
        switch step.kind {
        case .fixedTime:
            var time = "Fixed"
            if let h = step.hour, let m = step.minute { time = String(format: "Fixed • %02d:%02d", h, m) }
            let days = daysText(for: step)
            return days.isEmpty ? time : "\(time) • \(days)"
        case .timer:
            if let s = step.durationSeconds {
                if let n = step.everyNDays, n > 1 {
                    return "Timer • \(format(seconds: s)) • every \(n) days"
                }
                return "Timer • \(format(seconds: s))"
            }
            return "Timer"
        case .relativeToPrev:
            if let s = step.offsetSeconds { return "After previous • +\(format(seconds: s))" }
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

// MARK: - Share helper

private struct ShareView: View {
    let url: URL
    var body: some View {
        ShareLink(item: url) {
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up").font(.largeTitle)
                Text(url.lastPathComponent).font(.headline).lineLimit(2)
            }
            .padding()
        }
    }
}
