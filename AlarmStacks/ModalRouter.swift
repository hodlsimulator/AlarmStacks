//
//  ModalRouter.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import Combine
import SwiftData

@MainActor
final class ModalRouter: ObservableObject {
    static let shared = ModalRouter()

    /// What caused the paywall to appear?
    enum PaywallTrigger: Equatable {
        case unknown
        case stacks     // user hit the free stack cap
        case steps      // user hit the free steps-per-stack cap
    }

    /// Top-level modal kinds the app can present.
    enum SheetKind: String, Identifiable {
        case settings
        case addStack
        case addStep
        case paywall

        var id: String { rawValue }
    }

    /// Currently active sheet.
    @Published var activeSheet: SheetKind? = nil

    /// When presenting the Add Step sheet, this holds the target stack.
    @Published var addStepTarget: Stack? = nil

    /// Why did we open the paywall? (Used to tailor copy.)
    @Published var paywallTrigger: PaywallTrigger = .unknown

    // MARK: - Plain presenters

    func showSettings() { activeSheet = .settings }
    func showAddStack() { activeSheet = .addStack }

    /// Present the Paywall, with an optional trigger (default `.unknown`).
    func showPaywall(trigger: PaywallTrigger = .unknown) {
        paywallTrigger = trigger
        activeSheet = .paywall
    }

    /// Present the Add Step sheet directly (no gating).
    func showAddStep(for stack: Stack) {
        addStepTarget = stack
        activeSheet = .addStep
    }

    /// Dismiss whatever is showing and clear transient state.
    func dismiss() {
        activeSheet = nil
        addStepTarget = nil
        paywallTrigger = .unknown
    }

    // MARK: - Gated presenter for adding a step

    /// Call this from any “+ Add Step” button.
    /// If free tier and the stack already has 3 steps, it opens the Paywall instead of the Add Step sheet.
    func presentAddStep(for stack: Stack) {
        if !Store.shared.isPlus && stack.steps.count >= FreeTier.stepsPerStackLimit {
            addStepTarget = nil
            paywallTrigger = .steps
            activeSheet = .paywall
        } else {
            addStepTarget = stack
            activeSheet = .addStep
        }
    }
}
