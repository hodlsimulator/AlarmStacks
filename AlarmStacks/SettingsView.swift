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

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults for new steps") {
                    Toggle("Allow Snooze", isOn: $settings.defaultAllowSnooze)
                    Stepper(value: $settings.defaultSnoozeMinutes, in: 1...30) {
                        Text("Snooze Minutes: \(settings.defaultSnoozeMinutes)")
                    }
                    Text("These are just defaults for newly created steps. Each step’s own snooze value overrides this.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                SoundSettingsSection()

                // Appearance selector
                AppearancePickerView()

                // Debug toggles
                DebugSettingsSection()
                
                Section("Alarm loudness") {
                    Button("Ring a test alarm in 5 seconds") {
                        Task { _ = await AlarmKitScheduler.shared.scheduleTestRing(in: 5) }
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Alarms use your iPhone’s **Ringer & Alerts** volume. To keep them loud, raise the slider in **Settings → Sounds & Haptics** and consider turning **Change with Buttons** off so accidental button presses don’t lower it. If alarms seem to fade when you look at the phone, turn off **Attention Aware Features** in **Settings → Face ID & Attention**.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Single diagnostics entry (kept inside the Form so we don’t duplicate it)
                Section("Diagnostics") {
                    NavigationLink("Diagnostics Log") { DiagnosticsLogView() }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
