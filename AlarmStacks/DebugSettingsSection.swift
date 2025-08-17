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
    @AppStorage("debug.minReliableLeadForAK") private var minLeadForAK: Int = 75

    var body: some View {
        Section("Debug") {
            Toggle("Force UserNotifications (disable AlarmKit)", isOn: $forceUN)
            Toggle("Enable Live Activities", isOn: $liveActivitiesEnabled)
            Stepper("Min lead for AlarmKit: \(minLeadForAK)s",
                    value: $minLeadForAK, in: 30...300, step: 5)
            Text("Auto uses UN under this lead. Increase if AK jitters.").font(.footnote).foregroundStyle(.secondary)
            NavigationLink("Diagnostics") { DiagnosticsView() }
        }
    }
}
