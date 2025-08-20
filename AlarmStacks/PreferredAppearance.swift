//
//  PreferredAppearance.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Appearance mode

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

// MARK: - Theme tint

private func tintColor(for name: String) -> Color {
    switch name {
    case "Default":  return Color(red: 0.04, green: 0.52, blue: 1.00) // iOS blue
    case "Forest":   return Color(red: 0.16, green: 0.62, blue: 0.39)
    case "Coral":    return Color(red: 0.98, green: 0.45, blue: 0.35)

    case "Indigo":   return Color(red: 0.35, green: 0.37, blue: 0.80)
    case "Grape":    return Color(red: 0.56, green: 0.27, blue: 0.68)
    case "Mint":     return Color(red: 0.22, green: 0.77, blue: 0.58)
    case "Flamingo": return Color(red: 1.00, green: 0.35, blue: 0.62)
    case "Slate":    return Color(red: 0.36, green: 0.42, blue: 0.49)
    case "Midnight": return Color(red: 0.10, green: 0.14, blue: 0.28)

    default:         return Color(red: 0.04, green: 0.52, blue: 1.00)
    }
}

// MARK: - Host modifier

private struct PreferredAppearanceHost: ViewModifier {
    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")     private var themeName: String = "Default"

    @ViewBuilder
    func body(content: Content) -> some View {
        switch AppearanceMode(rawValue: mode) ?? .system {
        case .system:
            content
                .tint(tintColor(for: themeName))
        case .light:
            content
                .environment(\.colorScheme, .light)
                .tint(tintColor(for: themeName))
        case .dark:
            content
                .environment(\.colorScheme, .dark)
                .tint(tintColor(for: themeName))
        }
    }
}

#if os(iOS)
// MARK: - UIKit bridge (only for forced Light/Dark; System uses remount trick)

private final class _StyleBox {
    var applied: UIUserInterfaceStyle = .unspecified
}

private struct SheetStyleBridge: UIViewControllerRepresentable {
    var style: UIUserInterfaceStyle  // .light or .dark

    func makeCoordinator() -> _StyleBox { _StyleBox() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isHidden = true
        vc.view.isUserInteractionEnabled = false
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        guard context.coordinator.applied != style else { return }
        context.coordinator.applied = style

        guard let host = vc.parent else { return }
        if host.overrideUserInterfaceStyle != style {
            host.overrideUserInterfaceStyle = style
        }
        if let nav = host.navigationController,
           nav.overrideUserInterfaceStyle != style {
            nav.overrideUserInterfaceStyle = style
        }
    }

    static func dismantleUIViewController(_ vc: UIViewController, coordinator: _StyleBox) {
        if let host = vc.parent {
            host.overrideUserInterfaceStyle = .unspecified
            host.navigationController?.overrideUserInterfaceStyle = .unspecified
        }
    }
}
#endif

// MARK: - SHEET modifier (apply at presenter: GlobalSheetsHost)

private struct PreferredAppearanceSheet: ViewModifier {
    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")     private var themeName: String = "Default"

    @ViewBuilder
    func body(content: Content) -> some View {
        switch AppearanceMode(rawValue: mode) ?? .system {
        case .system:
            // System: no explicit forcing; host remount in GlobalSheetsHost rebuilds card with current scheme.
            content
                .tint(tintColor(for: themeName))

        case .light:
            #if os(iOS)
            content
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.light)
                .tint(tintColor(for: themeName))
                .background(SheetStyleBridge(style: .light).frame(width: 0, height: 0))
            #else
            content
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.light)
                .tint(tintColor(for: themeName))
            #endif

        case .dark:
            #if os(iOS)
            content
                .environment(\.colorScheme, .dark)
                .preferredColorScheme(.dark)
                .tint(tintColor(for: themeName))
                .background(SheetStyleBridge(style: .dark).frame(width: 0, height: 0))
            #else
            content
                .environment(\.colorScheme, .dark)
                .preferredColorScheme(.dark)
                .tint(tintColor(for: themeName))
            #endif
        }
    }
}

// MARK: - Public helpers

extension View {
    func preferredAppearanceHost() -> some View { modifier(PreferredAppearanceHost()) }
    func preferredAppearanceSheet() -> some View { modifier(PreferredAppearanceSheet()) }
}
    