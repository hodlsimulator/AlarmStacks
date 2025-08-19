//
//  GlobalSheetsHost.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import SwiftData

/// Presents all app-wide sheets from a stable host so appearance flips
/// don’t dismiss the sheet.
struct GlobalSheetsHost: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var systemScheme

    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")      private var themeName: String = "Default"

    @State private var settingsDetent: PresentationDetent = .medium

    private var appearanceID: String {
        "\(mode)-\(systemScheme == .dark ? "dark" : "light")-\(themeName)"
    }

    @EnvironmentObject private var router: ModalRouter

    var body: some View {
        Color.clear
            .sheet(item: $router.activeSheet) { which in
                switch which {
                case .settings:
                    SettingsView()
                        .id(appearanceID) // ← force remount so System clears Light immediately
                        .preferredAppearanceSheet()
                        .presentationDetents(
                            Set([PresentationDetent.medium, PresentationDetent.large]),
                            selection: $settingsDetent
                        )

                case .addStack:
                    AddStackSheet { newStack in
                        modelContext.insert(newStack)
                        try? modelContext.save()
                    }
                    .id(appearanceID)
                    .preferredAppearanceSheet()
                    .presentationDetents(Set([PresentationDetent.medium, PresentationDetent.large]))

                case .paywall:
                    PaywallView()
                        .id(appearanceID)
                        .preferredAppearanceSheet()
                        .presentationDetents(Set([PresentationDetent.medium, PresentationDetent.large]))
                }
            }
            .transaction { $0.disablesAnimations = true } // avoid flicker on remount
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
