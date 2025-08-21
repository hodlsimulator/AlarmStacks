//
//  ForegroundRearmCoordinator.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData

struct ForegroundRearmCoordinator: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Stack.createdAt, order: .reverse) private var stacks: [Stack]

    var body: some View {
        Color.clear
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { @MainActor in
                        await AlarmScheduler.shared.rescheduleAll(
                            stacks: stacks,
                            calendar: Calendar.current   // ✅ avoid “.current” inference error
                        )
                    }
                }
            }
    }
}
