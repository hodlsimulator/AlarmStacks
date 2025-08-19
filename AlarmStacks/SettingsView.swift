//
//  SettingsView.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = Settings.shared
    @StateObject private var store = Store.shared
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                // Premium / Plus
                Section {
                    HStack {
                        Label(store.isPlus ? "AlarmStacks Plus" : "Get AlarmStacks Plus", systemImage: store.isPlus ? "star.fill" : "star")
                            .foregroundStyle(store.isPlus ? .yellow : .primary)
                        Spacer()
                        if !store.isPlus {
                            Button("Learn more") { showingPaywall = true }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text("Active").foregroundStyle(.secondary)
                        }
                    }
                }

                // Themes (tint colour only; Plus unlocks extra themes)
                ThemePickerView()

                // Appearance selector (light/dark/system)
                AppearancePickerView()

                // Defaults for new steps
                Section("Defaults for new steps") {
                    Toggle("Allow Snooze", isOn: $settings.defaultAllowSnooze)
                    Stepper(value: $settings.defaultSnoozeMinutes, in: 1...30) {
                        Text("Snooze Minutes: \(settings.defaultSnoozeMinutes)")
                    }
                    Text("These are just defaults for newly created steps. Each step’s own snooze value overrides this.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Sound info (system default only; custom tones removed)
                SoundSettingsSection()

                // Debug toggles
                DebugSettingsSection()

                // Alarm loudness guidance
                Section("Alarm loudness") {
                    Button("Ring a test alarm in 5 seconds") {
                        Task { _ = await AlarmKitScheduler.shared.scheduleTestRing(in: 5) }
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Alarms use your iPhone’s **Ringer & Alerts** volume. To keep them loud, raise the slider in **Settings → Sounds & Haptics** and consider turning **Change with Buttons** off so accidental button presses don’t lower it. If alarms seem to fade when you look at the phone, turn off **Attention Aware Features** in **Settings → Face ID & Attention**.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Diagnostics
                Section("Diagnostics") {
                    NavigationLink("Diagnostics Log") { DiagnosticsLogView() }
                }

                if !store.isPlus {
                    Section {
                        Button("Restore Purchases") { Task { await store.restore() } }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await store.load() }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
