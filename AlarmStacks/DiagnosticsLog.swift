//
//  DiagnosticsLog.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI
import UIKit
import UserNotifications

enum DiagLog {
    private static let key = "diag.log.lines"
    private static let maxLines = 400

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Append a line.
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

    /// UN summary (pending + delivered counts).
    static func auditUN() async {
        let c = UNUserNotificationCenter.current()
        let pending = await c.pendingNotificationRequests()
        let delivered = await c.deliveredNotifications()
        log("UN audit pending=\(pending.count) delivered=\(delivered.count)")
    }
}

struct DiagnosticsLogView: View {
    @State private var lines: [String] = DiagLog.read()
    private var joined: String { lines.joined(separator: "\n\n") }

    var body: some View {
        ScrollView {
            Text(joined.isEmpty ? "No entries yet." : joined)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled) // selectable / copyable
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
                .contextMenu {
                    Button("Copy All") { UIPasteboard.general.string = joined }
                    ShareLink(item: joined) { Label("Share…", systemImage: "square.and.arrow.up") }
                }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Clear") {
                    DiagLog.clear()
                    lines = []
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Copy") { UIPasteboard.general.string = joined }
                ShareLink(item: joined) { Text("Share") }
                Button("Refresh") { refresh(withAudits: true) }
            }
        }
        .onAppear { refresh(withAudits: false) }
    }

    private func refresh(withAudits: Bool) {
        lines = DiagLog.read()
        if withAudits {
            Task {
                await DiagLog.auditUN()
                AlarmController.shared.auditAKNow()
                lines = DiagLog.read()
            }
        }
    }
}
