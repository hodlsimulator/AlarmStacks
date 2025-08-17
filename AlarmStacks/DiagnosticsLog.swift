//
//  DiagnosticsLog.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
import SwiftUI

/// Tiny ring buffer stored in UserDefaults so you can read it inside the app.
@MainActor
enum DiagLog {
    private static let key = "diag.lines.v1"
    private static let maxCount = 300

    static func log(_ msg: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(msg)"
        var lines = UserDefaults.standard.stringArray(forKey: key) ?? []
        lines.append(line)
        if lines.count > maxCount { lines.removeFirst(lines.count - maxCount) }
        UserDefaults.standard.set(lines, forKey: key)
    }

    static func lines() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Simple UI to view/copy logs (optional; link it from Settings).
struct DiagnosticsView: View {
    @State private var lines: [String] = []

    var body: some View {
        List(lines.reversed(), id: \.self) { Text($0).font(.caption.monospaced()) }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Refresh") { lines = DiagLog.lines() }
                    Button("Clear")   { DiagLog.clear(); lines = [] }
                }
            }
            .task { lines = DiagLog.lines() }
    }
}
