//
//  AlarmSanitiser.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//

import Foundation
import os.log

/// Production-safe reconciler:
/// - Never cancels alarms solely because they’re **untracked** (logs only).
/// - Still cleans up broken/snooze-orphans/expired/old-generation.
/// - Writes are MainActor-isolated to avoid Swift 6 concurrency warnings.
@MainActor
public final class AlarmSanitiser {

    public static let shared = AlarmSanitiser()

    public enum Mode {
        case logOnly   // never cancels (diagnostic)
        case active    // cancels for safe reasons, but NOT for "untracked"
    }

    public enum Reason: String {
        case launch
        case foreground
    }

    // Lightweight log level so we can reduce console noise by default.
    public enum LogLevel {
        case off
        case summary
        case verbose
    }

    /// Adjust this if you want more/less console output.
    public var logLevel: LogLevel = {
        #if DEBUG
        return .summary
        #else
        return .summary
        #endif
    }()

    /// If true, also echo to stdout (`print`). Off by default to avoid Xcode spam.
    public var echoToConsole: Bool = {
        #if DEBUG
        return false
        #else
        return false
        #endif
    }()

    // MARK: - Configuration

    /// Inject a canceller to actually stop system timers for a given id.
    /// You should set this once at app start.
    public var canceller: ((String) -> Void)?

    /// Controls whether we actually cancel or just log. In Release we allow
    /// cancellation for safe reasons (never for "untracked").
    public var mode: Mode = {
        #if DEBUG
        return .logOnly
        #else
        return .active
        #endif
    }()

    // MARK: - Storage plumbing

    private let std: UserDefaults
    private let grp: UserDefaults?

    private init(standard: UserDefaults = .standard,
                 appGroup: UserDefaults? = nil) {
        self.std = standard
        if let appGroup {
            self.grp = appGroup
        } else {
            // Call on the main actor to avoid Swift 6 isolation errors.
            self.grp = AlarmSanitiser.resolveAppGroupDefaults()
        }
    }

    private static func resolveAppGroupDefaults() -> UserDefaults? {
        // Try common Info.plist keys if you don’t want to hardcode the suite.
        let candidateKeys = ["AppGroupIdentifier", "AppGroupSuiteName", "ApplicationGroupIdentifier"]
        for key in candidateKeys {
            if let suite = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               let ud = UserDefaults(suiteName: suite) {
                return ud
            }
        }
        return nil
    }

    // MARK: - Public entrypoint

    /// Run a full audit/cleanup pass. Call on cold start and on every foreground.
    public func run(reason: Reason) {
        let started = Date()
        logSAN("launch=\(reason.rawValue) mode=\(modeString) notif=\(notifStateString)", level: .summary)

        // 1) Snapshot universe of keys from both stores
        let allKeys = keysUnion()
        let now = Date()
        let expiryCutoff = now.addingTimeInterval(-120)

        // 2) Collect tracked lists (alarmkit.ids.<stackID>)
        var trackedByStack: [String: [String]] = [:]
        var listLocation: [String: StoreKind] = [:] // where to write back
        for key in allKeys where key.hasPrefix("alarmkit.ids.") {
            let stackID = String(key.dropFirst("alarmkit.ids.".count))
            if let (arr, whereFrom) = readStringArray(forKey: key) {
                let ids = arr.filter { !$0.isEmpty }
                trackedByStack[stackID] = ids
                listLocation[stackID] = whereFrom
            }
        }
        let trackedIDs: Set<String> = Set(trackedByStack.values.flatMap { $0 })

        // 3) Find metadata-bearing IDs (ak.*)
        let metaIDs = collectMetaIDs(from: allKeys)

        // 4) Required fields
        let idsNeedingStack = metaIDs.filter { !hasString("ak.stackID.\($0)") }
        let idsNeedingKind  = metaIDs.filter { !hasString("ak.kind.\($0)") }
        let brokenIDs = Set(idsNeedingStack).union(idsNeedingKind)

        // 5) Untracked IDs (present in metadata, but not tracked by any stack)
        let untrackedIDs = Set(metaIDs).subtracting(trackedIDs)

        // 6) Snooze orphans
        let snoozeMap = readSnoozeMap(from: allKeys)
        var snoozeOrphans = Set<String>()
        for (_, snoozeID) in snoozeMap {
            if !trackedIDs.contains(snoozeID) {
                snoozeOrphans.insert(snoozeID)
            }
        }

        // 7) Expired IDs (eligible if expected OR effTarget < cutoff)
        var expiredIDs = Set<String>()
        for id in metaIDs {
            let exp = readTime("ak.expected.\(id)")
            let eff = readTime("ak.effTarget.\(id)")
            if let e = exp, e < expiryCutoff {
                expiredIDs.insert(id)
            } else if let e2 = eff, e2 < expiryCutoff {
                expiredIDs.insert(id)
            }
        }

        // 8) Generation sweep
        let globalGen = readInt("ak.generation")
        var oldGenIDs = Set<String>()
        if let g = globalGen {
            for id in metaIDs {
                if let ig = readInt("ak.generation.\(id)"), ig < g {
                    oldGenIDs.insert(id)
                }
            }
        }

        // 9) Decide actions
        var toCancel: [(id: String, reason: String)] = []
        var reasonsByID: [String: String] = [:]

        func enqueue(_ set: Set<String>, _ reason: String) {
            for id in set where reasonsByID[id] == nil {
                reasonsByID[id] = reason
                toCancel.append((id, reason))
            }
        }

        // Safe/destructive reasons (allowed in .active)
        enqueue(brokenIDs, "broken")
        enqueue(snoozeOrphans, "snooze_orphan")
        enqueue(oldGenIDs, "old_generation")
        enqueue(expiredIDs, "expired")

        // NEVER destructive for "untracked" — log only (verbose).
        if !untrackedIDs.isEmpty {
            for id in untrackedIDs {
                logSAN("untracked id=\(id) — NOT cancelling (log-only)", level: .verbose)
            }
        }

        // 10) Apply (cancel + wipe)
        var cancelledIDs = Set<String>()
        for tup in toCancel {
            if mode == .active {
                cancelAndWipe(id: tup.id, reason: tup.reason)
            } else {
                logSAN("would-cancel id=\(tup.id) reason=\(tup.reason)", level: .verbose)
            }
            cancelledIDs.insert(tup.id)
        }

        // 11) Enforce single-snooze invariant
        var changedStacks = Set<String>()

        for (baseID, snoozeID) in snoozeMap {
            guard let stack = readString("ak.stackID.\(baseID)"), !stack.isEmpty else { continue }
            var list = trackedByStack[stack] ?? []
            let hadBase = list.contains(baseID)
            let hasSnooze = list.contains(snoozeID)

            if hadBase && !hasSnooze {
                if let idx = list.firstIndex(of: baseID) {
                    list.remove(at: idx)
                    list.insert(snoozeID, at: idx)
                }
                trackedByStack[stack] = list
                changedStacks.insert(stack)
                logSAN("repair tracked swap stack=\(stack) base=\(baseID) -> snooze=\(snoozeID)", level: .verbose)
            } else if hadBase && hasSnooze {
                trackedByStack[stack] = list.filter { $0 != baseID }
                changedStacks.insert(stack)
                logSAN("repair tracked dedupe stack=\(stack) dropBase=\(baseID)", level: .verbose)
            }
        }

        // 12) Compact lists: remove cancelled + dedupe (stable)
        for (stack, ids) in trackedByStack {
            let before = ids
            var seen = Set<String>()
            var out: [String] = []
            out.reserveCapacity(ids.count)
            for id in ids {
                if cancelledIDs.contains(id) { continue }
                if !seen.contains(id) {
                    seen.insert(id)
                    out.append(id)
                }
            }
            if out != before {
                trackedByStack[stack] = out
                changedStacks.insert(stack)
            }
        }

        // 13) Write back lists if changed
        for stack in changedStacks {
            let ids = trackedByStack[stack] ?? []
            let loc = listLocation[stack] ?? (grp != nil ? .group : .standard)
            writeStringArray(ids, forStack: stack, to: loc)
            logSAN("wrote tracked list stack=\(stack) count=\(ids.count)", level: .verbose)
        }

        // 14) Snapshot counts (summary)
        let orphanCount = untrackedIDs.count
        let brokenCount = brokenIDs.count
        let snozCount = snoozeOrphans.count
        let expiredCount = expiredIDs.count
        let oldGenCount = oldGenIDs.count

        logSAN(
            "snapshot tracked=\(trackedIDs.count) meta=\(metaIDs.count) " +
            "orphans=\(orphanCount) broken=\(brokenCount) snoozeOrphans=\(snozCount) " +
            "expired=\(expiredCount) oldGen=\(oldGenCount) cancelled=\(cancelledIDs.count)",
            level: .summary
        )

        // 15) Recon hint (summary)
        if let next = computeNextPendingID(from: trackedByStack) {
            let df = ISO8601DateFormatter()
            logRECON("found next id=\(next.id) date=\(df.string(from: next.date))", level: .summary)
        } else {
            logRECON("no next id (idle)", level: .summary)
        }

        // 16) Done (summary)
        let durMs = Int(Date().timeIntervalSince(started) * 1000)
        logSAN("end elapsedMs=\(durMs)", level: .summary)
    }

    // MARK: - Internals

    private enum StoreKind { case standard, group }

    private func keysUnion() -> Set<String> {
        var set = Set(std.dictionaryRepresentation().keys)
        if let grp {
            // Note: dictionaryRepresentation() on group stores can log a harmless cfprefsd message
            // on first access in some environments; this is acceptable for our diagnostic pass.
            set.formUnion(grp.dictionaryRepresentation().keys)
        }
        return set
    }

    private func readString(_ key: String) -> String? {
        if let grp, let v = grp.string(forKey: key) { return v }
        return std.string(forKey: key)
    }

    private func readInt(_ key: String) -> Int? {
        if let grp, grp.object(forKey: key) != nil { return grp.integer(forKey: key) }
        if std.object(forKey: key) != nil { return std.integer(forKey: key) }
        return nil
    }

    private func readDouble(_ key: String) -> Double? {
        if let grp, grp.object(forKey: key) != nil { return grp.double(forKey: key) }
        if std.object(forKey: key) != nil { return std.double(forKey: key) }
        return nil
    }

    private func hasString(_ key: String) -> Bool {
        if let grp, grp.object(forKey: key) != nil { return grp.string(forKey: key) != nil }
        return std.string(forKey: key) != nil
    }

    private func readTime(_ key: String) -> Date? {
        if let d = readDouble(key) {
            return Date(timeIntervalSince1970: d)
        }
        if let i = readInt(key) {
            return Date(timeIntervalSince1970: TimeInterval(i))
        }
        return nil
    }

    private func readStringArray(forKey key: String) -> ([String], StoreKind)? {
        if let grp, let arr = grp.array(forKey: key) as? [String] {
            return (arr, .group)
        }
        if let arr = std.array(forKey: key) as? [String] {
            return (arr, .standard)
        }
        return nil
    }

    private func writeStringArray(_ arr: [String], forStack stack: String, to whereFrom: StoreKind) {
        let key = "alarmkit.ids.\(stack)"
        switch whereFrom {
        case .standard: std.set(arr, forKey: key)
        case .group: grp?.set(arr, forKey: key)
        }
    }

    private func removeKey(_ key: String) {
        std.removeObject(forKey: key)
        grp?.removeObject(forKey: key)
    }

    private func collectMetaIDs(from keys: Set<String>) -> Set<String> {
        var ids = Set<String>()
        func collect(suffixFrom key: String, prefix: String) {
            let id = String(key.dropFirst(prefix.count))
            if !id.isEmpty { ids.insert(id) }
        }
        for k in keys {
            if k.hasPrefix("ak.stackID.")   { collect(suffixFrom: k, prefix: "ak.stackID.") }
            if k.hasPrefix("ak.kind.")      { collect(suffixFrom: k, prefix: "ak.kind.") }
            if k.hasPrefix("ak.expected.")  { collect(suffixFrom: k, prefix: "ak.expected.") }
            if k.hasPrefix("ak.effTarget.") { collect(suffixFrom: k, prefix: "ak.effTarget.") }
            if k.hasPrefix("ak.offsetFromFirst.") { collect(suffixFrom: k, prefix: "ak.offsetFromFirst.") }
            if k.hasPrefix("ak.generation.") { collect(suffixFrom: k, prefix: "ak.generation.") }
        }
        // Also include any snoozeID values
        let sm = readSnoozeMap(from: keys)
        for (_, snoozeID) in sm where !snoozeID.isEmpty {
            ids.insert(snoozeID)
        }
        return ids
    }

    private func readSnoozeMap(from keys: Set<String>) -> [String: String] {
        var map: [String: String] = [:] // baseID -> snoozeID
        for k in keys where k.hasPrefix("ak.snooze.map.") {
            let baseID = String(k.dropFirst("ak.snooze.map.".count))
            if let v = readString(k), !baseID.isEmpty, !v.isEmpty {
                map[baseID] = v
            }
        }
        return map
    }

    private func cancelAndWipe(id: String, reason: String) {
        logSAN("cancel id=\(id) reason=\(reason)", level: .verbose)
        // 1) Cancel underlying timer (if a canceller is provided)
        if let canceller { canceller(id) }

        // 2) Wipe all ak.* keys with suffix .<id>
        let allKeys = keysUnion()
        for key in allKeys {
            if key.hasSuffix(".\(id)") && key.hasPrefix("ak.") {
                removeKey(key)
            }
        }
        // 3) Also remove from any snooze map entries that point to this id
        for key in allKeys where key.hasPrefix("ak.snooze.map.") {
            if readString(key) == id {
                removeKey(key)
            }
        }
    }

    private func computeNextPendingID(from trackedByStack: [String: [String]]) -> (id: String, date: Date)? {
        var best: (String, Date)?
        for ids in trackedByStack.values {
            for id in ids {
                let d = readTime("ak.effTarget.\(id)") ?? readTime("ak.expected.\(id)")
                if let date = d {
                    if best == nil || date < best!.1 {
                        best = (id, date)
                    }
                }
            }
        }
        return best
    }

    // MARK: - Logging

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AlarmStacks", category: "SAN")

    private func shouldLog(_ level: LogLevel) -> Bool {
        switch (logLevel, level) {
        case (.off, _):            return false
        case (.summary, .verbose): return false
        default:                   return true
        }
    }

    private func logSAN(_ message: String, level: LogLevel = .verbose) {
        guard shouldLog(level) else { return }
        logger.log("[SAN] \(message, privacy: .public)")
        if echoToConsole { print("[SAN] \(message)") }
    }

    private func logRECON(_ message: String, level: LogLevel = .verbose) {
        guard shouldLog(level) else { return }
        logger.log("[RECON] \(message, privacy: .public)")
        if echoToConsole { print("[RECON] \(message)") }
    }

    private var modeString: String {
        switch mode {
        case .logOnly: return "logOnly"
        case .active:  return "active"
        }
    }

    private var notifStateString: String {
        #if DEBUG
        return "debug_build"
        #else
        return "disabled"
        #endif
    }
}
