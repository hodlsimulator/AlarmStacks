//
//  SoundSettingsSection.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI

struct SoundSettingsSection: View {
    var body: some View {
        Section("Alarm sound") {
            LabeledContent("Sound") {
                Text("System default")
                    .foregroundStyle(.secondary)
            }
            Text("The system alarm sound loops indefinitely and overrides Silent/Focus. Custom tones are not used.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
