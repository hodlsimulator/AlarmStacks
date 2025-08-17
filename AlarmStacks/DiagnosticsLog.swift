//
//  DiagnosticsLog.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI

enum DiagLog {
    private static let key = "diag.log.lines"
    private static let maxLines = 400

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Append a line (thread-safe enough for our usage).
    static func log(_ message: String) {
        let line = "[\(iso.string(from: Date()))] \(message)"
        var lines = UserDefaults.standard.stringArray(forKey: key) ?? []
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        UserDefaults.standard.set(lines, forKey: key)
    }

    static func read() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct DiagnosticsLogView: View {
    @State private var lines: [String] = DiagLog.read()

    var body: some View {
        ScrollView {
            Text(lines.joined(separator: "\n\n"))
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                )
                .padding()
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") { lines = DiagLog.read() }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Clear") {
                    DiagLog.clear()
                    lines = []
                }
            }
        }
    }
}
