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
                        Label(store.isPlus ? "AlarmStacks Plus" : "Get AlarmStacks Plus",
                              systemImage: store.isPlus ? "star.fill" : "star")
                            .foregroundStyle(store.isPlus ? .yellow : .primary)
                            .singleLineTightTail()
                        Spacer()
                        if !store.isPlus {
                            Button("Learn more") { showingPaywall = true }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text("Active")
                                .foregroundStyle(.secondary)
                                .singleLineTightTail()
                        }
                    }
                }

                // Themes (Plus unlocks extra)
                ThemePickerView { showingPaywall = true }

                // Appearance selector (system / light / dark)
                AppearancePickerView()

                // Defaults for new steps
                Section("Defaults for new steps") {
                    Toggle("Allow Snooze", isOn: $settings.defaultAllowSnooze)
                    Stepper(value: $settings.defaultSnoozeMinutes, in: 1...30) {
                        Text("Snooze Minutes: \(settings.defaultSnoozeMinutes)")
                            .singleLineTightTail()
                    }
                    Text("These are just defaults for newly created steps. Each step’s own snooze value overrides this.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .singleLineTightTail()
                }

                // Sound info
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
                        .singleLineTightTail()
                }

                // Diagnostics
                Section("Diagnostics") {
                    NavigationLink("Diagnostics Log") { DiagnosticsLogView() }
                }

                // About / Version
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionString)
                            .foregroundStyle(.secondary)
                            .singleLineTightTail()
                    }
                }

                if !store.isPlus {
                    Section { Button("Restore Purchases") { Task { await store.restore() } } }
                }
            }
            // Let the sheet show system Liquid Glass; don’t paint the sheet.
            .scrollContentBackground(.hidden)

            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.large)

            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }

            .task { await store.load() }
        }
        // IMPORTANT: Do NOT call .preferredAppearanceSheet() here.
        // It’s applied at the presenter (GlobalSheetsHost) so “System” mirrors the host scheme live.

        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .preferredAppearanceSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
