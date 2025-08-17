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
    @AppStorage("debug.shadowFallbackEnabled") private var shadowEnabled = false // NEW

    var body: some View {
        Section("Debug") {
            Toggle("Force UserNotifications (disable AlarmKit)", isOn: $forceUN)
            Toggle("Enable Live Activities", isOn: $liveActivitiesEnabled)
            Toggle("Enable shadow fallback banner", isOn: $shadowEnabled) // default OFF
        }
    }
}
