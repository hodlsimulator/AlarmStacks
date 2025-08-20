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

// MARK: - Brand tint (pure Swift, no UIKit initialisers)

private struct RGB { let r: Double, g: Double, b: Double }

private func baseRGB(for name: String) -> RGB {
    switch name {
    case "Default":  return RGB(r: 0.04, g: 0.52, b: 1.00) // iOS blue
    case "Forest":   return RGB(r: 0.16, g: 0.62, b: 0.39)
    case "Coral":    return RGB(r: 0.98, g: 0.45, b: 0.35)

    case "Indigo":   return RGB(r: 0.35, g: 0.37, b: 0.80)
    case "Grape":    return RGB(r: 0.56, g: 0.27, b: 0.68)
    case "Mint":     return RGB(r: 0.22, g: 0.77, b: 0.58)
    case "Flamingo": return RGB(r: 1.00, g: 0.35, b: 0.62)
    case "Slate":    return RGB(r: 0.36, g: 0.42, b: 0.49)
    case "Midnight": return RGB(r: 0.10, g: 0.14, b: 0.28)

    default:         return RGB(r: 0.04, g: 0.52, b: 1.00)
    }
}

private func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { min(max(x, a), b) }

private func rgbToHsv(_ c: RGB) -> (h: Double, s: Double, v: Double) {
    let maxv = max(c.r, max(c.g, c.b))
    let minv = min(c.r, min(c.g, c.b))
    let delta = maxv - minv

    var h: Double = 0
    let s: Double = maxv == 0 ? 0 : (delta / maxv)
    let v: Double = maxv

    if delta != 0 {
        if maxv == c.r {
            h = (c.g - c.b) / delta + (c.g < c.b ? 6 : 0)
        } else if maxv == c.g {
            h = (c.b - c.r) / delta + 2
        } else {
            h = (c.r - c.g) / delta + 4
        }
        h /= 6
    }
    return (h, s, v)
}

private func hsvToRgb(h: Double, s: Double, v: Double) -> RGB {
    if s == 0 { return RGB(r: v, g: v, b: v) }
    let hh = (h - floor(h)) * 6
    let i = Int(hh)
    let f = hh - Double(i)
    let p = v * (1 - s)
    let q = v * (1 - s * f)
    let t = v * (1 - s * (1 - f))
    switch i % 6 {
    case 0: return RGB(r: v, g: t, b: p)
    case 1: return RGB(r: q, g: v, b: p)
    case 2: return RGB(r: p, g: v, b: t)
    case 3: return RGB(r: p, g: q, b: v)
    case 4: return RGB(r: t, g: p, b: v)
    default:return RGB(r: v, g: p, b: q)
    }
}

/// Slightly brightens dark-mode tint so `.borderedProminent` won’t flip to white on some iOS 26 betas.
private func elevatedForDarkMode(_ rgb: RGB, minBrightness: Double = 0.72, maxSaturation: Double = 0.92) -> RGB {
    var (h, s, v) = rgbToHsv(rgb)
    s = clamp(s, 0, maxSaturation)
    v = max(v, minBrightness)
    return hsvToRgb(h: h, s: s, v: v)
}

private func brandTint(for name: String, scheme: ColorScheme) -> Color {
    let base = baseRGB(for: name)
    let rgb = (scheme == .dark) ? elevatedForDarkMode(base) : base
    return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
}

// MARK: - Host modifier

private struct PreferredAppearanceHost: ViewModifier {
    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")     private var themeName: String = "Default"
    @Environment(\.colorScheme)  private var systemScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        switch AppearanceMode(rawValue: mode) ?? .system {
        case .system:
            content
                .tint(brandTint(for: themeName, scheme: systemScheme))

        case .light:
            content
                .environment(\.colorScheme, .light)
                .tint(brandTint(for: themeName, scheme: .light))

        case .dark:
            content
                .environment(\.colorScheme, .dark)
                .tint(brandTint(for: themeName, scheme: .dark))
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
    @Environment(\.colorScheme)  private var systemScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        switch AppearanceMode(rawValue: mode) ?? .system {
        case .system:
            content
                .tint(brandTint(for: themeName, scheme: systemScheme))

        case .light:
            #if os(iOS)
            content
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.light)
                .tint(brandTint(for: themeName, scheme: .light))
                .background(SheetStyleBridge(style: .light).frame(width: 0, height: 0))
            #else
            content
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.light)
                .tint(brandTint(for: themeName, scheme: .light))
            #endif

        case .dark:
            #if os(iOS)
            content
                .environment(\.colorScheme, .dark)
                .preferredColorScheme(.dark)
                .tint(brandTint(for: themeName, scheme: .dark))
                .background(SheetStyleBridge(style: .dark).frame(width: 0, height: 0))
            #else
            content
                .environment(\.colorScheme, .dark)
                .preferredColorScheme(.dark)
                .tint(brandTint(for: themeName, scheme: .dark))
            #endif
        }
    }
}

// MARK: - Public helpers

extension View {
    func preferredAppearanceHost() -> some View { modifier(PreferredAppearanceHost()) }
    func preferredAppearanceSheet() -> some View { modifier(PreferredAppearanceSheet()) }
}
