//
//  SoundSettingsSection.swift
//  AlarmStacks
//
//  Created by . . on 8/18/25.
//

import SwiftUI

struct SoundSettingsSection: View {
    @State private var choice: String =
        UserDefaults.standard.string(forKey: "app.preferredSoundName") ?? "system"

    private var bundledPulseFilename: String? {
        if resourceExists(named: "Pulse_01.caf") { return "Pulse_01.caf" }
        if resourceExists(named: "Pulse_01.wav") { return "Pulse_01.wav" }
        return nil
    }

    private var options: [(title: String, value: String)] {
        var items: [(String, String)] = [("System default", "system")]
        if let pulse = bundledPulseFilename {
            items.append(("Pulse_01", pulse))
        }
        return items
    }

    var body: some View {
        Section("Alarm sound") {
            Picker("Sound", selection: $choice) {
                ForEach(options, id: \.value) { opt in
                    Text(opt.title).tag(opt.value)
                }
            }
            .onAppear {
                // Normalise if previously chosen file is missing
                if choice != "system", !resourceExists(named: choice) {
                    choice = "system"
                    UserDefaults.standard.set("system", forKey: "app.preferredSoundName")
                }
            }
            // iOS 17+ onChange (two-parameter closure)
            .onChange(of: choice) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "app.preferredSoundName")
            }

            Button("Ring a test alarm in 5 seconds") {
                Task { _ = await AlarmKitScheduler.shared.scheduleTestRing(in: 5) }
            }
            .buttonStyle(.borderedProminent)

            if bundledPulseFilename == nil {
                Text("Add **Pulse_01.caf** or **Pulse_01.wav** to the app target to enable the custom tone option.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func resourceExists(named filename: String) -> Bool {
        let ns = filename as NSString
        let name = ns.deletingPathExtension
        let ext  = ns.pathExtension.isEmpty ? nil : ns.pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext) != nil
    }
}
