//
//  DebugSettingsSection.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI

struct DebugSettingsSection: View {
    @AppStorage("debug.forceUNFallback") private var forceUN = false
    @AppStorage("debug.liveActivitiesEnabled") private var liveActivitiesEnabled = true

    var body: some View {
        Section("Debug") {
            Toggle("Force UserNotifications (disable AlarmKit)", isOn: $forceUN)
            Toggle("Enable Live Activities", isOn: $liveActivitiesEnabled)
        }
    }
}
