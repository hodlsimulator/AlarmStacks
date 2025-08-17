//
//  DiagnosticsLog.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
import SwiftUI

enum DiagLog {
    private static let key = "diag.lines.v2"
    private static let maxLines = 200

    private static let ts: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func log(_ message: String) {
        let line = "[\(ts.string(from: Date()))] \(message)"
        var lines = UserDefaults.standard.stringArray(forKey: key) ?? []
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        UserDefaults.standard.set(lines, forKey: key)
    }

    static func all() -> String {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).joined(separator: "\n\n")
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct DiagnosticsView: View {
    @State private var text = DiagLog.all()

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No diagnostics yet." : text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding()
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Refresh") { text = DiagLog.all() } }
            ToolbarItem(placement: .topBarTrailing) { Button("Clear") { DiagLog.clear(); text = "" } }
        }
    }
}
