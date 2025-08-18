//
//  DebugSettingsSection.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI

struct DebugSettingsSection: View {
    @AppStorage("debug.forceUNFallback") private var forceUN = false
    @AppStorage("debug.alwaysUseAK") private var alwaysAK = false
    @AppStorage("debug.liveActivitiesEnabled") private var liveActivitiesEnabled = true
    @AppStorage("debug.minReliableLeadForAK") private var minLeadForAK: Int = 75

    var body: some View {
        Section("Debug") {
            Toggle("Force UserNotifications (disable AlarmKit)", isOn: $forceUN)
            Toggle("Always use AlarmKit (ignore min-lead)", isOn: $alwaysAK)
            Toggle("Enable Live Activities", isOn: $liveActivitiesEnabled)
            Stepper("Min lead for AK: \(minLeadForAK)s", value: $minLeadForAK, in: 30...180, step: 5)
                .help("Below this lead, scheduler prefers UN unless 'Always use AK' is on")
        }
    }
}
