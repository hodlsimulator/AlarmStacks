//
//  EmptyState.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import SwiftUI

/// Shown when there are no stacks yet.
struct EmptyState: View {
    var addSamples: () -> Void
    var createNew: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.largeTitle)

            Text("No stacks yet")
                .font(.headline)
                .singleLineTightTail()

            Text("Create a stack or add sample ones to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .singleLineTightTail()

            HStack(spacing: 10) {
                Button("Add Sample Stacks", action: addSamples)
                Button("Create New", action: createNew)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
}
