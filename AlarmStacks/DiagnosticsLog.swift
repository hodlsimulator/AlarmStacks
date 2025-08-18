//
//  DiagnosticsLog.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI
import UIKit
import UserNotifications

// MARK: - Diagnostics logging (local time + monotonic uptime)

@MainActor
enum DiagLog {
    private static let key = "diag.log.lines"
    private static let maxLines = 800

    private static let local: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"   // local with offset, e.g. +01:00
        f.timeZone = .current
        return f
    }()

    /// Format a date in local time with offset.
    static func f(_ date: Date) -> String { local.string(from: date) }

    /// Append a line with a stable prelude: local timestamp + monotonic uptime.
    static func log(_ message: String) {
        let now = Date()
        let up  = ProcessInfo.processInfo.systemUptime
        let stamp = "\(local.string(from: now)) | up:\(String(format: "%.3f", up))s"
        let line = "[\(stamp)] \(message)"
        var lines = UserDefaults.standard.stringArray(forKey: key) ?? []
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        UserDefaults.standard.set(lines, forKey: key)
    }

    static func read() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// UN summary (pending + delivered counts).
    static func auditUN() async {
        let c = UNUserNotificationCenter.current()
        let pending = await c.pendingNotificationRequests()
        let delivered = await c.deliveredNotifications()
        log("UN audit pending=\(pending.count) delivered=\(delivered.count)")
    }
}

// MARK: - AlarmKit diagnostics record (persist target wall time + target uptime per id)

@MainActor
enum AKDiag {
    private static func key(_ id: UUID) -> String { "ak.record.\(id.uuidString)" }

    struct Record: Codable {
        var stackName: String
        var stepTitle: String
        var scheduledAt: Date
        var scheduledUptime: TimeInterval
        var targetDate: Date
        var targetUptime: TimeInterval
        var seconds: Int
    }

    static func save(id: UUID, record: Record) {
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: key(id))
        }
    }

    static func load(id: UUID) -> Record? {
        guard let data = UserDefaults.standard.data(forKey: key(id)) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    static func remove(id: UUID) { UserDefaults.standard.removeObject(forKey: key(id)) }
}

// MARK: - UI: selectable/copyable diagnostics viewer

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
