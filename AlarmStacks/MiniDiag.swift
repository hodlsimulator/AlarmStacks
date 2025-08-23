//
//  MiniDiag.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
import OSLog

enum MiniDiag {
    private static let suite = UserDefaults(suiteName: "group.com.hodlsimulator.alarmstacks") ?? .standard
    private static let key = "diag.log.lines"
    private static let maxLines = 2000
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AlarmStacks",
                                       category: "Diag")

    private static let local: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        return f
    }()

    @inline(__always)
    static func log(_ message: @autoclosure () -> String) {
        let now = Date()
        let up  = ProcessInfo.processInfo.systemUptime
        let stamp = "\(local.string(from: now)) | up:\(String(format: "%.3f", up))s"
        let line = "[\(stamp)] \(message())"

        // Persist to App Group so the in-app log viewer can read it.
        var lines = suite.stringArray(forKey: key) ?? []
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        suite.set(lines, forKey: key)

        // Also to unified system log for convenience.
        logger.info("\(line, privacy: .public)")
    }
}
