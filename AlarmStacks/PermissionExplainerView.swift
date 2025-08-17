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
                    // Gate a one-shot re-arm when user returns from Settings
                    SettingsRearmGate.mark()
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
            return "To ring loudly and show a large banner when you’re in another app, notifications must be enabled. Turn them on in Settings. For best results, enable Time-Sensitive and set Banner Style to Persistent."
        case .alarmkit:
            return "Alarm permission is required for AlarmKit alerts. Turn it on in Settings. If it’s off or unavailable, the app falls back to standard notifications."
        }
    }

    private var iconName: String {
        switch kind {
        case .notifications: return "bell.slash"
        case .alarmkit:      return "alarm.waves.left.and.right"
        }
    }
}
