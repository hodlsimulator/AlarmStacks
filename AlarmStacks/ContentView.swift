//
//  ContentView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var systemScheme
    @Environment(\.scenePhase)   private var scenePhase
    @EnvironmentObject private var router: ModalRouter
    @Query(sort: \Stack.createdAt, order: .reverse) private var stacks: [Stack]

    @StateObject private var store = Store.shared
    @Namespace private var sheetNS

    private let freeStackLimit = 2

    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")      private var themeName: String = "Default"
    private var appearanceID: String { "\(mode)-\(systemScheme == .dark ? "dark" : "light")-\(themeName)" }

    @State private var renamingStack: Stack?
    @State private var newName: String = ""
    @State private var armingError: String?
    @State private var stepToEditViaMenu: Step?

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
                                router.showPaywall(trigger: .stacks)
                            } else { addSampleStacksCapped() }
                        },
                        createNew: {
                            if !store.isPlus && stacks.count >= freeStackLimit {
                                router.showPaywall(trigger: .stacks)
                            } else { router.showAddStack() }
                        }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        Toggle(
                            isOn: Binding(
                                get: { bulkState == .all && !stacks.isEmpty },
                                set: { on in Task { @MainActor in if on { await armAll() } else { await disarmAll() } } }
                            )
                        ) {
                            HStack(spacing: 8) {
                                Image(systemName: "bell.fill")
                                Text("All stacks armed").layoutPriority(1).singleLineTightTail()
                                if bulkState == .some {
                                    Text("(Mixed)").font(.footnote).foregroundStyle(.secondary).singleLineTightTail()
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)

                    ForEach(stacks) { stack in
                        StackRowCard(
                            stack: stack,
                            onToggleArm: { Task { await toggleArm(forID: stack.id) } },
                            onDuplicate: { duplicate(stack: stack) },
                            onRename: { beginRename(stack) },
                            onDelete: { delete(stack: stack) },
                            onEditStep: { step in stepToEditViaMenu = step },
                            onDuplicateStep: { step in duplicate(step: step) },
                            onToggleStepEnabled: { step in Task { await toggleStepEnabled(step) } },
                            canArm: canArm(stack:)
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { delete(stack: stack) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    if !store.isPlus {
                        Section {
                            HStack {
                                Label("Free limit: 2 stacks", systemImage: "star")
                                    .foregroundStyle(.secondary)
                                    .singleLineTightTail()
                                Spacer()
                                Button("Get Plus") { router.showPaywall(trigger: .stacks) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollClipDisabled()
            .themedSurface()
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTapAnywhere()
            .navigationTitle("Alarm Stacks")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) { VersionBadge().allowsHitTesting(false) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.showSettings() } label: { Label("Settings", systemImage: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if !store.isPlus && stacks.count >= freeStackLimit { router.showPaywall(trigger: .stacks) }
                        else { router.showAddStack() }
                    } label: { Label("Add Stack", systemImage: "plus") }
                    .matchedTransitionSource(id: "addStack", in: sheetNS)
                }
            }
            .navigationDestination(for: Stack.self) { stack in StackDetailView(stack: stack) }
            .navigationDestination(for: Step.self) { step in StepEditorView(step: step) }
            .navigationDestination(item: $stepToEditViaMenu) { step in StepEditorView(step: step) }
            .alert("Couldn’t arm this stack", isPresented: Binding(get: { armingError != nil }, set: { if !$0 { armingError = nil } })) {
                Button("OK", role: .cancel) { armingError = nil }
            } message: { Text(armingError ?? "") }
        }
        .background(ThemeSurfaceBackground())
        .task { await store.load() }
        .syncThemeToAppGroup()
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { LiveActivityManager.resyncThemeForActiveActivities() } }
        }
        .sheet(item: $renamingStack) { s in
            NavigationStack {
                Form { TextField("Name", text: $newName).singleLineTightTail() }
                    .navigationTitle("Rename Stack")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { renamingStack = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                s.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                                try? modelContext.save()
                                renamingStack = nil
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
            .preferredAppearanceSheet()
        }
    }

    // MARK: - Preflight

    @MainActor private func canArm(stack: Stack) -> Bool {
        if let first = stack.sortedSteps.first, first.kind == .relativeToPrev { return false }
        return nextStart(for: stack) != nil
    }

    @MainActor private func nextStart(for stack: Stack) -> Date? {
        let base = Date()
        for step in stack.sortedSteps where step.isEnabled {
            switch step.kind {
            case .fixedTime, .timer, .relativeToPrev:
                if let d = try? step.nextFireDate(basedOn: base, calendar: .current) { return d }
                else { return nil }
            }
        }
        return nil
    }

    // MARK: - Helpers

    @MainActor private func liveStack(by id: UUID) -> Stack? {
        let fd = FetchDescriptor<Stack>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(fd).first
    }

    // MARK: - Stack actions

    @MainActor private func armAll() async {
        for s in stacks where !s.isArmed {
            guard canArm(stack: s) else {
                armingError = "“\(s.name)” needs a valid starting step (e.g. a fixed time)."
                continue
            }
            s.isArmed = true
            try? modelContext.save()
            await AlarmScheduler.shared.cancelAll(for: s)
            let ok = (try? await AlarmScheduler.shared.schedule(stack: s, calendar: .current)) != nil
            if !ok { s.isArmed = false; try? modelContext.save(); armingError = "Couldn’t arm “\(s.name)”." }
        }
    }

    @MainActor private func disarmAll() async {
        for s in stacks where s.isArmed {
            s.isArmed = false
            try? modelContext.save()
            await AlarmScheduler.shared.cancelAll(for: s)
        }
    }

    @MainActor private func toggleArm(forID id: UUID) async {
        guard let s = liveStack(by: id) else { return }
        if s.isArmed {
            s.isArmed = false; try? modelContext.save()
            await AlarmScheduler.shared.cancelAll(for: s)
        } else {
            guard canArm(stack: s) else {
                armingError = "This stack doesn’t have a start I can schedule. Add a fixed time for the first step."
                return
            }
            s.isArmed = true; try? modelContext.save()
            await AlarmScheduler.shared.cancelAll(for: s)
            let ok = (try? await AlarmScheduler.shared.schedule(stack: s, calendar: .current)) != nil
            if !ok { s.isArmed = false; try? modelContext.save(); armingError = "Couldn’t arm “\(s.name)”." }
        }
    }

    private func delete(stack: Stack) {
        Task { @MainActor in
            await AlarmScheduler.shared.cancelAll(for: stack)
            modelContext.delete(stack)
            try? modelContext.save()
        }
    }

    private func beginRename(_ s: Stack) { renamingStack = s; newName = s.name }

    private func duplicate(stack: Stack) {
        var baseName = stack.name.isEmpty ? "Stack" : stack.name
        if baseName.lowercased().hasSuffix(" copy") == false { baseName += " copy" }
        var name = baseName; var counter = 2
        while stacks.contains(where: { $0.name == name }) { name = "\(baseName) \(counter)"; counter += 1 }

        let newStack = Stack(name: name); newStack.isArmed = false
        let now = Date()
        for (idx, src) in stack.sortedSteps.enumerated() {
            let step = Step(title: src.title, kind: src.kind, order: idx, createdAt: now,
                            hour: src.hour, minute: src.minute,
                            allowSnooze: src.allowSnooze, snoozeMinutes: src.snoozeMinutes, stack: newStack)
            step.durationSeconds = src.durationSeconds
            step.offsetSeconds = src.offsetSeconds
            step.weekday = src.weekday
            step.weekdays = src.weekdays
            step.everyNDays = src.everyNDays
            step.isEnabled = src.isEnabled
        }
        modelContext.insert(newStack)
        try? modelContext.save()
    }

    // MARK: - Step actions

    private func duplicate(step src: Step) {
        guard let stack = src.stack else { return }
        let now = Date()
        let new = Step(title: src.title, kind: src.kind, order: stack.sortedSteps.count, createdAt: now,
                       hour: src.hour, minute: src.minute,
                       allowSnooze: src.allowSnooze, snoozeMinutes: src.snoozeMinutes, stack: stack)
        new.durationSeconds = src.durationSeconds
        new.offsetSeconds = src.offsetSeconds
        new.weekday = src.weekday
        new.weekdays = src.weekdays
        new.everyNDays = src.everyNDays
        new.isEnabled = src.isEnabled
        try? modelContext.save()

        if stack.isArmed {
            Task { @MainActor in
                await AlarmScheduler.shared.cancelAll(for: stack)
                _ = try? await AlarmScheduler.shared.schedule(stack: stack, calendar: .current)
            }
        }
    }

    @MainActor private func toggleStepEnabled(_ step: Step) async {
        step.isEnabled.toggle()
        try? modelContext.save()
        if let stack = step.stack, stack.isArmed {
            await AlarmScheduler.shared.cancelAll(for: stack)
            _ = try? await AlarmScheduler.shared.schedule(stack: stack, calendar: .current)
        }
    }

    // MARK: - Samples

    private func addSampleStacksCapped() {
        var capacity = store.isPlus ? Int.max : (freeStackLimit - stacks.count)
        guard capacity > 0 else { return }
        let s1 = sampleMorning(); modelContext.insert(s1); capacity -= 1
        if capacity > 0 { let s2 = samplePomodoro(); modelContext.insert(s2); capacity -= 1 }
        try? modelContext.save()
    }

    private func sampleMorning() -> Stack {
        let s = Stack(name: "Morning")
        let now = Date(); let def = Settings.shared
        let start   = Step(title: "Start",   kind: .fixedTime,     order: 0, createdAt: now, hour: 6, minute: 30, allowSnooze: def.defaultAllowSnooze, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        let hydrate = Step(title: "Hydrate", kind: .relativeToPrev, order: 1, createdAt: now, offsetSeconds: 10*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        let stretch = Step(title: "Stretch", kind: .relativeToPrev, order: 2, createdAt: now, offsetSeconds: 5*60,  allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        let shower  = Step(title: "Shower",  kind: .relativeToPrev, order: 3, createdAt: now, offsetSeconds: 20*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        s.steps = [start, hydrate, stretch, shower]; return s
    }

    private func samplePomodoro() -> Stack {
        let s = Stack(name: "Pomodoro")
        let now = Date(); let def = Settings.shared
        s.steps = [
            Step(title: "Focus", kind: .relativeToPrev, order: 0, createdAt: now, offsetSeconds: 25*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s),
            Step(title: "Break", kind: .relativeToPrev, order: 1, createdAt: now, offsetSeconds: 5*60,  allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s),
            Step(title: "Focus", kind: .relativeToPrev, order: 2, createdAt: now, offsetSeconds: 25*60, allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s),
            Step(title: "Break", kind: .relativeToPrev, order: 3, createdAt: now, offsetSeconds: 5*60,  allowSnooze: false, snoozeMinutes: def.defaultSnoozeMinutes, stack: s)
        ]
        return s
    }
}

// MARK: - Stack Detail (unchanged UI, kept here to avoid extra file)

private struct StackDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var systemScheme
    @EnvironmentObject private var router: ModalRouter
    @State private var calendar = Calendar.current
    @State private var isBusy = false
    @Bindable var stack: Stack
    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")      private var themeName: String = "Default"
    private var appearanceID: String { "\(mode)-\(systemScheme == .dark ? "dark" : "light")-\(themeName)" }

    var body: some View {
        List {
            Section("Stack") {
                TextField("Name", text: $stack.name)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .singleLineTightTail()
                    .onSubmit { try? modelContext.save() }
                    .onChange(of: stack.name) { _, _ in try? modelContext.save() }
            }
            Section {
                Toggle(isOn: Binding(get: { stack.isArmed }, set: { newVal in
                    guard !isBusy else { return }
                    isBusy = true
                    Task { @MainActor in
                        if newVal {
                            if !canArm(stack: stack) {
                                stack.isArmed = false
                                try? modelContext.save()
                                isBusy = false
                                return
                            }
                            await AlarmScheduler.shared.cancelAll(for: stack)
                            if (try? await AlarmScheduler.shared.schedule(stack: stack, calendar: calendar)) != nil {
                                stack.isArmed = true
                            } else {
                                stack.isArmed = false
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
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTapAnywhere()
        .navigationTitle(stack.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.presentAddStep(for: stack) } label: {
                    Label("Add Step", systemImage: "plus")
                }
            }
        }
    }

    private func canArm(stack: Stack) -> Bool { nextStart(for: stack) != nil }

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
}

// MARK: - StepRow (unchanged visual semantics)

private struct StepRow: View {
    @Bindable var step: Step
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.headline).singleLineTightTail()
                Text(detailText(for: step))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .singleLineTightTail(minScale: 0.9)
            }
            Spacer(minLength: 8)
            Image(systemName: step.isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(step.isEnabled ? Color.accentColor : Color.secondary)
        }
        .padding(.vertical, 2)
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
                return s >= 0 ? "After previous • +\(format(seconds: s))"
                              : "Before previous • −\(format(seconds: -s))"
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
