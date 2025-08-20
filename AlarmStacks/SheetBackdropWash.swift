//
//  SheetBackdropWash.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI

/// A subtle full-screen wash shown **behind** modal sheets when the app forces
/// Light/Dark. In iOS 26 we let the system’s Liquid Glass read the true content.
struct SheetBackdropWash: View {
    @EnvironmentObject private var router: ModalRouter
    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue

    var body: some View {
        let selected = AppearanceMode(rawValue: mode) ?? .system
        let visible = router.activeSheet != nil && selected != .system

        Group {
            if visible {
                if #available(iOS 26.0, *) {
                    Color.clear // ← don’t flatten the background; keep Liquid Glass lively
                } else {
                    (selected == .light ? Color.white : Color.black)
                        .opacity(selected == .light ? 0.35 : 0.25) // softened a bit
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
