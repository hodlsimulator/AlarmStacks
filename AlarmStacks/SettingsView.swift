//
//  SettingsView.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme

    @StateObject private var settings = Settings.shared
    @StateObject private var store = Store.shared

    @State private var showingPaywall = false

    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")      private var themeName: String = "Default"

    private var appearanceID: String {
        "\(mode)-\(systemScheme == .dark ? "dark" : "light")-\(themeName)"
    }

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

                // Themes (Plus unlocks extra)
                ThemePickerView {
                    showingPaywall = true
                }

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
            .themedSurface()                // ← pastel background in BOTH schemes
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .id(appearanceID)           // rebuild when mode/system/theme changes
                .preferredAppearance()
                .presentationDetents([.medium, .large])
        }
    }
}
