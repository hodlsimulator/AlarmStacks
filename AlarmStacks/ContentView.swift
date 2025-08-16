//
//  ContentView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \AlarmStack.createdAt, order: .reverse) private var stacks: [AlarmStack]

    @StateObject private var scheduler = AlarmScheduler.shared
    @State private var lastScheduledIDs: [UUID] = []
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(stacks, id: \.id) { stack in
                    StackSectionView(stack: stack) {
                        startStack(stack)
                    }
                }
            }
            .navigationTitle("Alarm Stacks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Morning Stack") { addMorningStack() }
                        Button("Add Pomodoro Stack") { addPomodoroStack() }
                    } label: { Image(systemName: "plus.circle.fill") }
                }
                ToolbarItem(placement: .bottomBar) {
                    if !lastScheduledIDs.isEmpty {
                        Button(role: .destructive) {
                            scheduler.cancel(alarmIDs: lastScheduledIDs)
                            lastScheduledIDs.removeAll()
                        } label: { Label("Cancel Active", systemImage: "xmark.circle") }
                    } else {
                        EmptyView() // ensures the ToolbarItem always returns a view
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: { Text(errorText) }
            .task { try? await scheduler.requestAuthorizationIfNeeded() }
        }
    }

    private func startStack(_ stack: AlarmStack) {
        Task {
            do {
                lastScheduledIDs = try await scheduler.schedule(stack: stack)
            } catch {
                errorText = "Couldn’t schedule: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func addMorningStack() {
        let s = AlarmStack(
            name: "Morning — 45m",
            steps: [
                AlarmStep(title: "Wake", durationSeconds: 0, hour: 6, minute: 30, weekdays: [1,2,3,4,5], tintHex: "#34C759"),
                AlarmStep(title: "Hydrate", durationSeconds: 300, tintHex: "#0A84FF"),
                AlarmStep(title: "Stretch", durationSeconds: 480, tintHex: "#FF9F0A"),
                AlarmStep(title: "Shower", durationSeconds: 600, tintHex: "#AF52DE"),
                AlarmStep(title: "Leave", durationSeconds: 0, hour: 7, minute: 15, weekdays: [1,2,3,4,5], tintHex: "#FF2D55")
            ])
        ctx.insert(s)
        try? ctx.save()
    }

    private func addPomodoroStack() {
        let s = AlarmStack(
            name: "Focus — Pomodoro x2",
            steps: [
                AlarmStep(title: "Focus 25", durationSeconds: 25*60, tintHex: "#0A84FF"),
                AlarmStep(title: "Break 5", durationSeconds: 5*60, tintHex: "#34C759"),
                AlarmStep(title: "Focus 25", durationSeconds: 25*60, tintHex: "#0A84FF"),
                AlarmStep(title: "Break 5", durationSeconds: 5*60, tintHex: "#34C759")
            ])
        ctx.insert(s)
        try? ctx.save()
    }
}

private struct StackSectionView: View {
    let stack: AlarmStack
    let onStart: () -> Void

    var body: some View {
        Section {
            ForEach(stack.steps, id: \.id) { step in
                StepRow(step: step)
            }
            Button(action: onStart) {
                Label("Start This Stack", systemImage: "play.fill")
            }
        } header: {
            Text(stack.name)
        }
    }
}

private struct StepRow: View {
    let step: AlarmStep

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Spacer()
            Circle()
                .fill(Color(hex: step.tintHex))
                .frame(width: 14, height: 14)
        }
    }

    private var subtitle: String {
        if step.durationSeconds > 0 {
            return "\(step.durationSeconds) sec"
        } else if let h = step.hour, let m = step.minute {
            return String(format: "%02d:%02d", h, m)
        } else {
            return ""
        }
    }
}
