//
//  ForegroundRearmCoordinator.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI
import SwiftData

/// Invisible helper that re-arms ALL armed stacks only when the user returns
/// from Settings after tapping our explainer's button. It never runs otherwise.
struct ForegroundRearmCoordinator: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Color.clear
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, SettingsRearmGate.consume() {
                    Task { await rearmAllArmed() }
                }
            }
    }

    @MainActor
    private func rearmAllArmed() async {
        let stacks = (try? modelContext.fetch(FetchDescriptor<Stack>())) ?? []
        let armed = stacks.filter { $0.isArmed }
        guard !armed.isEmpty else { return }
        await AlarmScheduler.shared.rescheduleAll(stacks: armed, calendar: .current)
    }
}
