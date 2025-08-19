//
//  ModalRouter.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import Combine

@MainActor
final class ModalRouter: ObservableObject {
    static let shared = ModalRouter()
    enum SheetKind: String, Identifiable {
        case settings, addStack, paywall
        var id: String { rawValue }
    }

    @Published var activeSheet: SheetKind? = nil

    func showSettings() { activeSheet = .settings }
    func showAddStack() { activeSheet = .addStack }
    func showPaywall()  { activeSheet = .paywall  }
    func dismiss()      { activeSheet = nil       }
}
