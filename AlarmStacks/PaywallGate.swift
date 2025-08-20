//
//  PaywallGate.swift
//  AlarmStacks
//
//  Created by . . on 8/20/25.
//

import SwiftUI

/// Free tier limits (centralised).
enum FreeTier {
    /// Free users can create at most 3 steps in a stack. Attempting to add a 4th triggers Paywall.
    static let stepsPerStackLimit: Int = 3
}

@MainActor
enum PaywallGate {
    /// Guard for adding a step to a specific stack.
    @discardableResult
    static func canAddStep(toStackWith currentStepCount: Int,
                           isPlus: Bool,
                           router: ModalRouter) -> Bool {
        guard !isPlus else { return true }
        if currentStepCount >= FreeTier.stepsPerStackLimit {
            router.activeSheet = .paywall
            return false
        }
        return true
    }
}

/// Convenience button wrapper for UI.
struct PaywalledAddStepButton<Label: View>: View {
    let currentStepCount: Int
    @EnvironmentObject private var router: ModalRouter
    @StateObject private var store = Store.shared
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: {
            if PaywallGate.canAddStep(toStackWith: currentStepCount,
                                      isPlus: store.isPlus,
                                      router: router) {
                action()
            }
        }) {
            label()
        }
        .disabled(!store.isPlus && currentStepCount >= FreeTier.stepsPerStackLimit)
    }
}
