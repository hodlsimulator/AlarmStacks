//
//  PermissionExplainerView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI

enum PermissionKind {
    case notifications
    case alarmkit
}

struct PermissionExplainerView: View {
    let kind: PermissionKind

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: iconName)
                    .font(.largeTitle)
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button {
                    openAppSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Permission Needed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        switch kind {
        case .notifications: return "Notifications are Off"
        case .alarmkit:      return "Alarm Permission is Off"
        }
    }

    private var message: String {
        switch kind {
        case .notifications:
            return "To ring on time and let you snooze from the lock screen, notifications must be enabled. You can turn them on in Settings."
        case .alarmkit:
            return "Alarm permission is required for AlarmKit alerts. You can turn it on in Settings. If it stays off, the app will fall back to standard notifications."
        }
    }

    private var iconName: String {
        switch kind {
        case .notifications: return "bell.slash"
        case .alarmkit:      return "alarm.waves.left.and.right"
        }
    }
}
