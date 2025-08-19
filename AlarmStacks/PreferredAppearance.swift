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

// MARK: - Host modifier (environment only; never preferredColorScheme)

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
// MARK: - UIKit override for the SHEET host (instant, no dismissals)

private struct SheetUIStyleOverride: UIViewControllerRepresentable {
    var mode: AppearanceMode

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isHidden = true
        vc.view.isUserInteractionEnabled = false
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        let target: UIUserInterfaceStyle = {
            switch mode {
            case .system: return .unspecified
            case .light:  return .light
            case .dark:   return .dark
            }
        }()
        // Apply to the sheet’s hosting controller only.
        DispatchQueue.main.async {
            if let parent = vc.parent {
                parent.overrideUserInterfaceStyle = target
                parent.navigationController?.overrideUserInterfaceStyle = target
            }
        }
    }

    static func dismantleUIViewController(_ vc: UIViewController, coordinator: ()) {
        vc.parent?.overrideUserInterfaceStyle = .unspecified
        vc.parent?.navigationController?.overrideUserInterfaceStyle = .unspecified
    }
}
#else
private struct SheetUIStyleOverride: View {
    var mode: AppearanceMode
    var body: some View { EmptyView() }
}
#endif

// MARK: - Sheet modifier (drive chrome via UIKit; nudge SwiftUI env to match)

private struct PreferredAppearanceSheet: ViewModifier {
    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")     private var themeName: String = "Default"

    @ViewBuilder
    func body(content: Content) -> some View {
        let selected = AppearanceMode(rawValue: mode) ?? .system

        switch selected {
        case .system:
            content
                .background(SheetUIStyleOverride(mode: .system).frame(width: 0, height: 0))
                .tint(tintColor(for: themeName))  // no colorScheme override in System

        case .light:
            content
                .environment(\.colorScheme, .light)
                .background(SheetUIStyleOverride(mode: .light).frame(width: 0, height: 0))
                .tint(tintColor(for: themeName))

        case .dark:
            content
                .environment(\.colorScheme, .dark)
                .background(SheetUIStyleOverride(mode: .dark).frame(width: 0, height: 0))
                .tint(tintColor(for: themeName))
        }
    }
}

extension View {
    func preferredAppearanceHost() -> some View { modifier(PreferredAppearanceHost()) }
    func preferredAppearanceSheet() -> some View { modifier(PreferredAppearanceSheet()) }
}
