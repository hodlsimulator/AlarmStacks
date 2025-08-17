//
//  PreferredAppearance.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

struct PreferredAppearance: ViewModifier {
    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue

    func body(content: Content) -> some View {
        let scheme = AppearanceMode(rawValue: mode)?.colorScheme
        content.preferredColorScheme(scheme)
    }
}

extension View {
    func preferredAppearance() -> some View { modifier(PreferredAppearance()) }
}
