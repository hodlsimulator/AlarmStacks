//
//  AppearancePickerView.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI

struct AppearancePickerView: View {
    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance").font(.headline)
            Picker("Appearance", selection: $mode) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { m in
                    Text(m.title).tag(m.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 8)
    }
}
