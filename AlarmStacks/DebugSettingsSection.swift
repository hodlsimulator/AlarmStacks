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
    @AppStorage("debug.minReliableLeadForAK") private var minLeadForAK: Int = 75  // seconds

    var body: some View {
        Section("Debug") {
            Toggle("Force UserNotifications (disable AlarmKit)", isOn: $forceUN)
            Toggle("Enable Live Activities", isOn: $liveActivitiesEnabled)
            Stepper(value: $minLeadForAK, in: 30...600, step: 5) {
                Text("AK min reliable lead: \(minLeadForAK)s")
            }
        }
    }
}
