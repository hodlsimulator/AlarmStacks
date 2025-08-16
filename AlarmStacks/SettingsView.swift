//
//  SettingsView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = Settings.shared
    @State private var performingDisarm = false
    @State private var disarmError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults for new steps") {
                    Toggle("Allow Snooze", isOn: $settings.defaultAllowSnooze)
                    Stepper(value: $settings.defaultSnoozeMinutes, in: 1...30) {
                        Text("Snooze Minutes: \(settings.defaultSnoozeMinutes)")
                    }
                    .accessibilityHint("Changes will update any steps that are still using the previous default.")
                }

                Section("Alarms while unlocked") {
                    Toggle("Boost with notification sound (may duplicate)", isOn: $settings.boostUnlockedWithUN)
                    Text("Adds a same-moment notification sound alongside AlarmKit to make alarms harder to miss when you’re using the phone. Critical sound is used if allowed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Maintenance") {
                    Button {
                        Task { await rescheduleAllArmed() }
                    } label: {
                        Label("Reschedule All Armed Stacks", systemImage: "arrow.clockwise.circle")
                    }

                    Button(role: .destructive) {
                        Task { await disarmAll() }
                    } label: {
                        Label("Disarm All Stacks", systemImage: "bell.slash.fill")
                    }
                    .disabled(performingDisarm)
                }

                if let disarmError {
                    Section("Last Error") {
                        Text(disarmError).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: settings.defaultSnoozeMinutes) { old, new in
                propagateSnoozeDefaultChange(from: old, to: new)
            }
        }
    }

    // MARK: - Actions

    private func fetchStacks() -> [Stack] {
        (try? modelContext.fetch(FetchDescriptor<Stack>())) ?? []
    }

    private func fetchSteps() -> [Step] {
        (try? modelContext.fetch(FetchDescriptor<Step>())) ?? []
    }

    private func rescheduleAllArmed() async {
        let stacks = fetchStacks().filter { $0.isArmed }
        await AlarmScheduler.shared.rescheduleAll(stacks: stacks, calendar: .current)
    }

    private func disarmAll() async {
        performingDisarm = true
        defer { performingDisarm = false }
        let stacks = fetchStacks()
        for s in stacks where s.isArmed {
            await AlarmScheduler.shared.cancelAll(for: s)
            s.isArmed = false
        }
        do { try modelContext.save() }
        catch { disarmError = error.localizedDescription }
    }

    private func propagateSnoozeDefaultChange(from oldValue: Int, to newValue: Int) {
        var updated = 0
        for step in fetchSteps() where step.allowSnooze && step.snoozeMinutes == oldValue {
            step.snoozeMinutes = newValue
            updated += 1
        }
        if updated > 0 { try? modelContext.save() }
    }
}

