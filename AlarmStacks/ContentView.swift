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
    @Environment(\.colorScheme)  private var systemScheme
    @Environment(\.scenePhase)   private var scenePhase
    @Query(sort: \Stack.createdAt, order: .reverse) private var stacks: [Stack]

    @State private var showingAddStack = false
    @State private var showingSettings = false
    @State private var showingPaywall = false

    @StateObject private var store = Store.shared

    // Prevent overlapping schedule/cancel on the same stack from different UI entry points
    @State private var busyStacks: Set<UUID> = []

    // Keep the Settings sheet detent pinned even if the view updates
    @State private var settingsDetent: PresentationDetent = .medium
    
    @Namespace private var sheetNS

    private let freeStackLimit = 2

    // Forcing sheet rebuilds when appearance or theme changes
    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")      private var themeName: String = "Default"
    private var appearanceID: String {
        "\(mode)-\(systemScheme == .dark ? "dark" : "light")-\(themeName)"
    }

    // Bulk state used for the single toggle row
    private enum BulkState { case none, some, all }
    private var bulkState: BulkState {
        let total = stacks.count
        guard total > 0 else { return .none }
        let armed = stacks.filter { $0.isArmed }.count
        if armed == 0 { return .none }
        if armed == total { return .all }
        return .some
    }

    var body: some View {
        NavigationStack {
            List {
                if stacks.isEmpty {
                    EmptyState(
                        addSamples: {
                            if !store.isPlus && stacks.count >= freeStackLimit {
                                showingPaywall = true
                            } else {
                                addSampleStacksCapped()
                            }
                        },
                        createNew: {
                            if !store.isPlus && stacks.count >= freeStackLimit {
                                showingPaywall = true
                            } else {
                                showingAddStack = true
                            }
                        }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    // Global control: single toggle with clear, large hit area
                    Section {
                        Toggle(
                            isOn: Binding(
                                get: { bulkState == .all && !stacks.isEmpty },
                                set: { on in
                                    if on { armAll() } else { disarmAll() }
                                }
                            )
                        ) {
                            HStack(spacing: 8) {
                                Image(systemName: "bell.fill")
                                Text("All stacks armed")
                                    .layoutPriority(1)
                                    .singleLineTightTail()
                                if bulkState == .some {
                                    Text("(Mixed)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .singleLineTightTail()
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)

                    ForEach(stacks) { stack in
                        NavigationLink(value: stack) {
                            StackCard(color: stackAccent(for: stack)) {
                                StackRow(stack: stack)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
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

                    if !store.isPlus {
                        Section {
                            HStack {
                                Label("Free limit: 2 stacks", systemImage: "star")
                                    .foregroundStyle(.secondary)
                                    .singleLineTightTail()
                                Spacer()
                                Button("Get Plus") { showingPaywall = true }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .themedSurface() // colours the list itself

            .navigationTitle("Alarm Stacks")
            .navigationBarTitleDisplayMode(.large)

            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if !store.isPlus && stacks.count >= freeStackLimit {
                            showingPaywall = true
                        } else {
                            showingAddStack = true
                        }
                    } label: {
                        Label("Add Stack", systemImage: "plus")
                    }
                    // iOS 26: source for the zooming sheet transition
                    .matchedTransitionSource(id: "addStack", in: sheetNS)
                }
            }
            .navigationDestination(for: Stack.self) { stack in
                StackDetailView(stack: stack)
            }
            .navigationDestination(for: Step.self) { step in
                StepEditorView(step: step)
            }
        }
        // Apply theme background at the root so it shows under the large title & safe areas.
        .background(ThemeSurfaceBackground())

        .sheet(isPresented: $showingAddStack) {
            AddStackSheet { newStack in
                modelContext.insert(newStack)
                try? modelContext.save()
            }
            .id(appearanceID)
            .preferredAppearance()
            .presentationDetents([.medium, .large]) // Liquid Glass at partial height
            // iOS 26: destination of the zoom transition (morphs from the add button)
            .navigationTransition(.zoom(sourceID: "addStack", in: sheetNS))
        }

        // ✅ Settings: keep detent fixed + no remount on theme change
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .preferredAppearance()
                .presentationDetents([.medium, .large], selection: $settingsDetent)
        }

        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .id(appearanceID)
                .preferredAppearance()
                .presentationDetents([.medium, .large])
        }
        .task { await store.load() }

        // Ensure the theme is mirrored + live-activities recolour
        .syncThemeToAppGroup()
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await LiveActivityManager.resyncThemeForActiveActivities() }
            }
        }
    }

    // MARK: - Actions

    private func armAll() {
        Task { @MainActor in
            for s in stacks where !s.isArmed {
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

    private func addSampleStacksCapped() {
        var capacity = store.isPlus ? Int.max : (freeStackLimit - stacks.count)
        guard capacity > 0 else { return }

        let s1 = sampleMorning()
        modelContext.insert(s1); capacity -= 1
        if capacity > 0 {
            let s2 = samplePomodoro()
            modelContext.insert(s2); capacity -= 1
        }
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

// MARK: - Row (main list)

private struct StackRow: View {
    @Bindable var stack: Stack
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(stack.name)
                    .font(.headline)
                    .layoutPriority(1)
                    .singleLineTightTail() // keep name to one line / ellipsis

                if stack.isArmed {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .imageScale(.small)
                        .foregroundStyle(.tint)
                }

                Spacer()

                Text("\(stack.sortedSteps.count) step\(stack.sortedSteps.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .singleLineTightTail()
            }

            if let next = nextStart(for: stack) {
                Text("Next: \(formatted(next))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .singleLineTightTail()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stack.sortedSteps) { step in
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

    private func nextStart(for stack: Stack) -> Date? {
        let base = Date()
        for step in stack.sortedSteps where step.isEnabled {
            switch step.kind {
            case .fixedTime, .timer, .relativeToPrev:
                if let d = try? step.nextFireDate(basedOn: base, calendar: calendar) { return d }
                else { return nil }
            }
        }
        return nil
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

private struct StepChip: View {
    let step: Step

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: step)).imageScale(.small)
            Text(label(for: step))
                .font(.caption)
                .layoutPriority(1)
                .singleLineTightTail(minScale: 0.85)
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
            return days.isEmpty ? "\(time)  \(step.title)" : "\(time) • \(days)  \(step.title)"
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
        if let arr = step.weekdays, !arr.isEmpty { chosen = arr }
        else if let one = step.weekday { chosen = [one] }
        else { return "" }

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
    @Environment(\.colorScheme)  private var systemScheme
    @State private var calendar = Calendar.current
    @State private var showingAddSheet = false

    // Local busy flag to avoid overlapping cancel/reschedule from detail screen
    @State private var isBusy = false

    @Bindable var stack: Stack

    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")      private var themeName: String = "Default"
    private var appearanceID: String {
        "\(mode)-\(systemScheme == .dark ? "dark" : "light")-\(themeName)"
    }

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
                })) { Text("Armed").singleLineTightTail() }
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
        .listStyle(.insetGrouped)
        .themedSurface()
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
                .id(appearanceID)           // ensure rebuild on appearance changes
                .preferredAppearance()
                .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
    }
}

private struct StepRow: View {
    @Bindable var step: Step
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(step.title)
                    .font(.headline)
                    .singleLineTightTail()
                Text(detailText(for: step))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .singleLineTightTail(minScale: 0.9)
            }
            Spacer()
            Image(systemName: step.isEnabled ? "checkmark.circle.fill" : "xmark.circle")
        }
    }
    private func detailText(for: Step) -> String {
        let step = `for`
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
                if s >= 0 { return "After previous • +\(format(seconds: s))" }
                else { return "Before previous • −\(format(seconds: -s))" }
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
        if let arr = step.weekdays, !arr.isEmpty { chosen = arr }
        else if let one = step.weekday { chosen = [one] }
        else { return "" }
        let set = Set(chosen)
        if set.count == 7 { return "Every day" }
        if set == Set([2,3,4,5,6]) { return "Weekdays" }
        if set == Set([1,7]) { return "Weekend" }
        let order = [2,3,4,5,6,7,1]
        return order.filter { set.contains($0) }.compactMap { map[$0] }.joined(separator: " ")
    }
}

// MARK: - Cards, palette, background helpers

private struct StackCard<Content: View>: View {
    let color: Color
    let content: Content
    @Environment(\.colorScheme) private var scheme

    init(color: Color, @ViewBuilder _ content: () -> Content) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(color.opacity(scheme == .dark ? 0.55 : 0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.10), radius: 10, x: 0, y: 6)
    }
}

private func stackAccent(for stack: Stack) -> Color {
    // A gentle, readable pastel palette for per-stack accents.
    let palette: [Color] = [
        Color(red: 0.70, green: 0.83, blue: 1.00), // pastel blue
        Color(red: 0.74, green: 0.90, blue: 0.82), // pastel green
        Color(red: 1.00, green: 0.86, blue: 0.67), // pastel orange
        Color(red: 0.87, green: 0.79, blue: 0.99), // pastel purple
        Color(red: 1.00, green: 0.78, blue: 0.88), // pastel pink
        Color(red: 0.78, green: 0.92, blue: 0.92), // pastel teal
        Color(red: 0.81, green: 0.86, blue: 1.00), // pastel indigo
        Color(red: 1.00, green: 0.92, blue: 0.68)  // pastel yellow
    ]
    let idx = abs(stack.id.uuidString.hashValue) % palette.count
    return palette[idx]
}

// MARK: - Add Stack / Step (inline components so file compiles standalone)

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
                                Text("Timer").tag(StepKind.timer)
                                Text("After previous").tag(StepKind.relativeToPrev)
                            }
                            .pickerStyle(.segmented)

                            switch firstStepKind {
                            case .fixedTime:
                                // Wheel style => spin and tap Create once.
                                DatePicker("Time",
                                           selection: $firstStepTime,
                                           displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .id("firstStepWheel") // ← anchor for auto-scroll

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
                                    .singleLineTightTail()
                            }
                        }
                    }
                }
                // Liquid Glass: show translucent sheet material behind
                .scrollContentBackground(.hidden)
                .background(.clear)

                // Give a little breathing room at the bottom so the wheel isn't clipped.
                .contentMargins(.bottom, 36, for: .scrollContent)

                // Ensure the wheel is fully visible at .medium without changing detent.
                .onAppear {
                    if addFirstStep && firstStepKind == .fixedTime {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 60_000_000) // allow layout
                            withAnimation(.snappy) {
                                proxy.scrollTo("firstStepWheel", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: firstStepKind) { _, new in
                    if addFirstStep && new == .fixedTime {
                        withAnimation(.snappy) {
                            proxy.scrollTo("firstStepWheel", anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle("New Stack")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                    .disabled(addFirstStep && (firstStepKind != .fixedTime && totalSeconds == 0))
                }
            }
        }
    }

    // MARK: - Subviews

    private var durationEditors: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Duration") {
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
                step = Step(title: "Wake",
                            kind: .fixedTime,
                            order: order,
                            hour: c.hour, minute: c.minute,
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
                            .singleLineTightTail()
                    }
                }
            }
            // Liquid Glass: show translucent sheet material behind
            .scrollContentBackground(.hidden)
            .background(.clear)

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
            Text("No stacks yet").font(.headline).singleLineTightTail()
            Text("Create a stack or add sample ones to get started.")
                .foregroundStyle(.secondary)
                .singleLineTightTail()
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
