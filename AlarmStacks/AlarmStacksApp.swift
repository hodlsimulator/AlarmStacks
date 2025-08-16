//
//  AlarmStacksApp.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData

@main
struct AlarmStacksApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [AlarmStack.self, AlarmStep.self])
    }
}
