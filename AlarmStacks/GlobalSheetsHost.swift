//
//  GlobalSheetsHost.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Presents all app-wide sheets from a stable host so appearance flips
/// don’t dismiss the sheet.
struct GlobalSheetsHost: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var systemScheme   // host scheme (outside any sheet)

    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")      private var themeName: String = "Default"

    @State private var settingsDetent: PresentationDetent = .medium

    // Snapshot overlay to hide the brief rebuild when switching to System
    #if canImport(UIKit)
    @State private var snapshotImage: UIImage?
    @State private var showSnapshotOverlay = false
    #endif

    private var appearanceID: String {
        // Include host scheme so content remounts on host Light/Dark change
        "\(mode)-\(systemScheme == .dark ? "dark" : "light")-\(themeName)"
    }

    @EnvironmentObject private var router: ModalRouter

    // MARK: - Seamless remount to adopt System dark/light for the SHEET CARD
    private func remountSheetIfNeededForSystem() {
        guard (AppearanceMode(rawValue: mode) ?? .system) == .system else { return }
        guard let current = router.activeSheet else { return } // only if a sheet is up

        // Take a one-frame snapshot to cover the rebuild (prevents perceptible flash)
        captureSnapshot()

        // Re-present the same sheet without animation to make UIKit rebuild the card.
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { router.activeSheet = nil }

        DispatchQueue.main.async {
            var tx2 = Transaction()
            tx2.disablesAnimations = true
            withTransaction(tx2) { router.activeSheet = current }

            // Let the new card attach, then fade the snapshot away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                clearSnapshot()
            }
        }
    }

    var body: some View {
        Color.clear
            .sheet(item: $router.activeSheet) { which in
                switch which {
                case .settings:
                    SettingsView()
                        .id(appearanceID)                 // remount content on mode/scheme/theme
                        .preferredAppearanceSheet()       // drive sheet subtree style
                        .presentationDetents(
                            Set([.medium, .large]),
                            selection: $settingsDetent
                        )
                        .presentationDragIndicator(.visible)

                case .addStack:
                    AddStackSheet { newStack in
                        modelContext.insert(newStack)
                        try? modelContext.save()
                    }
                    .id(appearanceID)
                    .preferredAppearanceSheet()
                    .presentationDetents(Set([.medium, .large]))
                    .presentationDragIndicator(.visible)

                case .addStep:
                    if let stack = router.addStepTarget {
                        AddStepSheet(stack: stack)
                            .id(appearanceID)
                            .preferredAppearanceSheet()
                            .presentationDetents(Set([.medium, .large]))
                            .presentationDragIndicator(.visible)
                    } else {
                        // Defensive: avoid crashing if no target is present.
                        EmptyView()
                            .id(appearanceID)
                            .preferredAppearanceSheet()
                            .presentationDetents(Set([.medium, .large]))
                            .presentationDragIndicator(.visible)
                    }

                case .paywall:
                    PaywallView()
                        .id(appearanceID)
                        .preferredAppearanceSheet()
                        .presentationDetents(Set([.medium, .large]))
                        .presentationDragIndicator(.visible)
                }
            }
            .transaction { $0.disablesAnimations = true } // avoid flicker on remount
            .accessibilityHidden(true)
            .allowsHitTesting(false)

            // iOS 17+ onChange with two-parameter closure
            .onChange(of: mode) { _, _ in remountSheetIfNeededForSystem() }
            .onChange(of: systemScheme) { _, _ in remountSheetIfNeededForSystem() }

            // Snapshot overlay
            .overlay {
                #if canImport(UIKit)
                if showSnapshotOverlay, let image = snapshotImage {
                    Image(uiImage: image)
                        .resizable()
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                #endif
            }
    }

    // MARK: - Snapshot helpers (iOS only)
    #if canImport(UIKit)
    private func captureSnapshot() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let img = renderer.image { _ in
            // afterScreenUpdates: false avoids a re-layout jank
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        snapshotImage = img
        showSnapshotOverlay = true
    }

    private func clearSnapshot() {
        withAnimation(.linear(duration: 0.08)) {
            showSnapshotOverlay = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            snapshotImage = nil
        }
    }
    #endif
}
