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
    private var selectedMode: AppearanceMode { AppearanceMode(rawValue: mode) ?? .system }

    var body: some View {
        NavigationStack {
            Form {
                // Premium / Plus
                Section {
                    HStack {
                        Label(store.isPlus ? "AlarmStacks Plus" : "Get AlarmStacks Plus", systemImage: store.isPlus ? "star.fill" : "star")
                            .foregroundStyle(store.isPlus ? .yellow : .primary)
                            .singleLineTightTail()
                        Spacer()
                        if !store.isPlus {
                            Button("Learn more") { showingPaywall = true }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text("Active").foregroundStyle(.secondary).singleLineTightTail()
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

                if !store.isPlus {
                    Section {
                        Button("Restore Purchases") { Task { await store.restore() } }
                    }
                }
            }
            // ——————————————————————————————————————————————————————————————
            // IMPORTANT: Make the sheet OPAQUE only for Light/Dark so nothing
            // from the dark host bleeds through the glass. Keep glass for System.
            // ——————————————————————————————————————————————————————————————
            .applySheetFormBackground(for: selectedMode)

            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }

            // Ensure the nav bar text/buttons adopt the forced scheme when not System
            .applySheetToolbarStyle(for: selectedMode)

            .task { await store.load() }
        }
        // Don’t animate layout when switching appearance to avoid any jiggle
        .animation(nil, value: mode)

        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .id(appearanceID)
                .preferredAppearanceSheet() // you already apply sheet-wide appearance
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Sheet styling helpers (scoped to this file)

private struct SheetFormBackground: ViewModifier {
    let mode: AppearanceMode
    func body(content: Content) -> some View {
        switch mode {
        case .system:
            // Keep the "Liquid Glass" look, let it reflect the app behind.
            content
                .scrollContentBackground(.hidden)
                .background(.clear)
        case .light, .dark:
            // Make the sheet fully opaque so it cleanly flips to Light/Dark.
            content
                .scrollContentBackground(.visible)
                .background(Color(.systemGroupedBackground))
        }
    }
}

private struct SheetToolbarStyle: ViewModifier {
    let mode: AppearanceMode
    func body(content: Content) -> some View {
        #if os(iOS)
        switch mode {
        case .system:
            content
                .toolbarBackground(.automatic, for: .navigationBar)
        case .light:
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color(.systemBackground), for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
        case .dark:
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color(.systemBackground), for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
        #else
        content
        #endif
    }
}

private extension View {
    func applySheetFormBackground(for mode: AppearanceMode) -> some View {
        modifier(SheetFormBackground(mode: mode))
    }
    func applySheetToolbarStyle(for mode: AppearanceMode) -> some View {
        modifier(SheetToolbarStyle(mode: mode))
    }
}
