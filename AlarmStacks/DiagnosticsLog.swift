//
//  DiagnosticsLog.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
import SwiftUI
import UIKit
import UserNotifications
import ActivityKit

// Put tunables in a non-isolated container so they are safe to read anywhere.
public enum LATuning {
    /// Timer only when target is in the future by more than this epsilon.
    public static let timerEpsilon: TimeInterval = 0.4
}

// MARK: - App environment snapshot (active/inactive/background + lock state + scene counts)

@MainActor
enum AppEnv {

    static func snapshot() -> String {
        let app = UIApplication.shared

        // Map app state to a readable string
        let stateName: String = {
            switch app.applicationState {
            case .active:     return "active"
            case .inactive:   return "inactive"
            case .background: return "background"
            @unknown default: return "unknown"
            }
        }()

        // Foreground scene counts
        let scenes = app.connectedScenes.compactMap { $0 as? UIWindowScene }
        let fa = scenes.filter { $0.activationState == .foregroundActive   }.count
        let fi = scenes.filter { $0.activationState == .foregroundInactive }.count
        let ba = scenes.filter { $0.activationState == .background         }.count
        let un = scenes.filter { $0.activationState == .unattached         }.count

        // Lock state: public signal is "protectedDataAvailable"
        let locked = !app.isProtectedDataAvailable

        // High-level context guess
        let context: String = {
            if locked { return "LockScreen" }
            switch app.applicationState {
            case .active:     return "InApp"
            case .inactive:   return "SystemOverlayOrTransition"
            case .background: return "OtherAppOrHome"
            @unknown default: return "Unknown"
            }
        }()

        return "state=\(stateName) locked=\(locked ? "yes" : "no") scenes{fa=\(fa) fi=\(fi) bg=\(ba) un=\(un)} context=\(context)"
    }
}

// MARK: - Diagnostics logging (local time + monotonic uptime, merged with App Group)

@MainActor
enum DiagLog {
    private static let key = "diag.log.lines"
    private static let maxLines = 2000

    private static let local: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"   // e.g. 2025-08-20 16:10:06.726 +01:00
        return f
    }()

    // Lightweight clock-only (localised short time)
    private static let clockOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale.autoupdatingCurrent
        f.timeZone = .current
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static var group: UserDefaults? { UserDefaults(suiteName: AppGroups.main) }

    /// Format a date in local time with offset.
    static func f(_ date: Date) -> String { local.string(from: date) }

    /// Format a date as a user-facing clock time (e.g. “04:39”)
    static func clock(_ date: Date) -> String { clockOnly.string(from: date) }

    /// Append a line with a stable prelude: local timestamp + monotonic uptime.
    /// Writes to BOTH the app container and the App Group so the widget/extension can read it too.
    static func log(_ message: String) {
        let now = Date()
        let up  = ProcessInfo.processInfo.systemUptime
        let stamp = "\(local.string(from: now)) | up:\(String(format: "%.3f", up))s"
        let line = "[\(stamp)] \(message)"

        // Standard
        var a = UserDefaults.standard.stringArray(forKey: key) ?? []
        a.append(line)
        if a.count > maxLines { a.removeFirst(a.count - maxLines) }
        UserDefaults.standard.set(a, forKey: key)

        // App Group
        if let g = group {
            var b = g.stringArray(forKey: key) ?? []
            b.append(line)
            if b.count > maxLines { b.removeFirst(b.count - maxLines) }
            g.set(b, forKey: key)
        }
    }

    /// Read a merged view of the standard + group logs, de-duplicated and time-sorted.
    static func read() -> [String] {
        let a = UserDefaults.standard.stringArray(forKey: key) ?? []
        let b = group?.stringArray(forKey: key) ?? []
        var set = Set<String>()
        var merged = [String]()
        for line in (a + b) {
            if set.insert(line).inserted { merged.append(line) }
        }
        // Lexicographic sort works with our stable timestamp prefix.
        merged.sort()
        return merged
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        group?.removeObject(forKey: key)
    }

    /// UN summary (pending + delivered counts).
    static func auditUN() async {
        let c = UNUserNotificationCenter.current()
        let pending = await c.pendingNotificationRequests()
        let delivered = await c.deliveredNotifications()
        log("UN audit pending=\(pending.count) delivered=\(delivered.count)")
    }

    /// Environment stamp with app state/lock info.
    static func envStamp(_ reason: String) {
        let tz = TimeZone.current.identifier
        let lp = ProcessInfo.processInfo.isLowPowerModeEnabled ? "LP=on" : "LP=off"
        let env = AppEnv.snapshot()
        log("ENV \(reason) tz=\(tz) \(lp) \(env)")
    }
}

// MARK: - Live Activity diagnostics

@MainActor
enum LADiag {

    // MARK: Auth + active list

    /// Logs LA authorization and a compact list of currently active activities for our attributes.
    /// Call this right after request/update/end, and also on failures, to see if an activity exists.
    static func logAuthAndActive(from whereFrom: String, stackID: String? = nil, expectingAlarmID: String? = nil) {
        let info = ActivityAuthorizationInfo()
        let enabled = info.areActivitiesEnabled
        let acts = Activity<AlarmActivityAttributes>.activities

        // Summarise as "stackID:alarmID"
        let summary = acts.map { a in
            let sid = a.attributes.stackID
            let aid = a.content.state.alarmID
            return "\(sid):\(aid)"
        }.joined(separator: " ")

        let seenExpected: String = {
            guard let expect = expectingAlarmID, expect.isEmpty == false else { return "-" }
            return acts.contains(where: { $0.content.state.alarmID == expect }) ? "y" : "n"
        }()

        DiagLog.log("[ACT] state from=\(whereFrom) stack=\(stackID ?? "-") auth.enabled=\(enabled ? "y" : "n") active.count=\(acts.count) active{\(summary)} expecting=\(expectingAlarmID ?? "-") seen=\(seenExpected)")
    }

    // MARK: Timer direction + boundary

    // Wrapper with default epsilon (avoids default-arg evaluation issues in Swift 6).
    static func logTimer(whereFrom: String, start: Date?, end: Date, now: Date = Date()) {
        logTimer(whereFrom: whereFrom, start: start, end: end, now: now, epsilon: LATuning.timerEpsilon)
    }

    /// Core: explicit epsilon (callers may pass a custom tolerance).
    static func logTimer(whereFrom: String, start: Date?, end: Date, now: Date, epsilon: TimeInterval) {
        let rawRemain = end.timeIntervalSince(now)

        if let start {
            let elapsed = max(0, now.timeIntervalSince(start))
            DiagLog.log(String(
                format: "[ACT] timer where=%@ dir=up start=%@ end=%@ now=%@ remain=- elapsed=%.3fs",
                whereFrom, DiagLog.f(start), DiagLog.f(end), DiagLog.f(now), elapsed
            ))
        } else {
            let remain = max(0, rawRemain)
            DiagLog.log(String(
                format: "[ACT] timer where=%@ dir=down start=- end=%@ now=%@ remain=%.3fs elapsed=-s",
                whereFrom, DiagLog.f(end), DiagLog.f(now), remain
            ))
        }

        // Extra analysis line (does not replace the original one)
        let boundary = boundaryBucket(rawRemain: rawRemain, epsilon: epsilon)
        let willUseTimer = rawRemain > epsilon ? "y" : "n"
        DiagLog.log(String(
            format: "[ACT] timer.eval where=%@ eps=%.3fs rawRemain=%.3fs boundary=%@ willUseTimer=%@",
            whereFrom, epsilon, rawRemain, boundary, willUseTimer
        ))
    }

    /// Classify how close we are to the boundary (purely for diagnostics).
    private static func boundaryBucket(rawRemain: TimeInterval, epsilon: TimeInterval) -> String {
        if rawRemain > epsilon { return "PRE" }           // clearly before
        if rawRemain < -epsilon { return "POST" }         // clearly after
        return "BOUNDARY"                                 // within ±epsilon of target
    }

    // MARK: Render decision logging (what the UI will *actually* show)

    // Wrapper with default epsilon.
    static func logRenderDecision(
        surface: String,
        state st: AlarmActivityAttributes.ContentState,
        now: Date = Date()
    ) {
        logRenderDecision(surface: surface, state: st, epsilon: LATuning.timerEpsilon, now: now)
    }

    /// Core: explicit epsilon (callers may pass a custom tolerance).
    static func logRenderDecision(
        surface: String,
        state st: AlarmActivityAttributes.ContentState,
        epsilon: TimeInterval,
        now: Date
    ) {
        let rawRemain = st.ends.timeIntervalSince(now)
        let preFire   = rawRemain > epsilon
        let ringing   = (st.firedAt != nil)

        let chip = preFire ? "NEXT STEP" : (ringing ? "RINGING" : "NEXT STEP")
        let useTimer = preFire
        let clockDate = ringing ? (st.firedAt ?? st.ends) : st.ends
        let boundary  = boundaryBucket(rawRemain: rawRemain, epsilon: epsilon)
        let sinceFired = ringing ? now.timeIntervalSince(st.firedAt ?? now) : nil

        // Note: when useTimer==true we *count down* to st.ends; otherwise we show an absolute clock time.
        DiagLog.log(String(
            format: "[LA MODE] surface=%@ chip=%@ display=%@ eps=%.3fs boundary=%@ rawRemain=%.3fs preFire=%@ ringing=%@ " +
                    "ends.clock=%@ firedAt.clock=%@ chosen.clock=%@ timer.to=%@ " +
                    "stack=%@ step=%@ id=%@",
            surface,
            chip,
            useTimer ? "timer" : "clock",
            epsilon,
            boundary,
            rawRemain,
            preFire ? "y" : "n",
            ringing ? "y" : "n",
            DiagLog.clock(st.ends),
            st.firedAt.map(DiagLog.clock) ?? "-",
            DiagLog.clock(clockDate),
            useTimer ? DiagLog.clock(st.ends) : "-",
            st.stackName,
            st.stepTitle,
            st.alarmID.isEmpty ? "-" : st.alarmID
        ))

        if let sinceFired {
            DiagLog.log(String(
                format: "[LA MODE+] surface=%@ sinceFired=%.3fs firedAt=%@",
                surface, sinceFired, DiagLog.f(st.firedAt!)
            ))
        }
    }

    /// Optional: Log a compact-trailing sample of what’s being drawn (helps catch wrapping/width growth).
    static func logCompactTrailingSample(surface: String, drawnText: String) {
        let count = drawnText.count
        let hasColon = drawnText.contains(":") ? "y" : "n"
        DiagLog.log("[LA CT] surface=\(surface) sample=\"\(drawnText)\" chars=\(count) colon=\(hasColon)")
    }
}

// MARK: - Live Activity smoke test (to separate OS quirks from app behaviour)

/// Minimal attributes used only by the smoke test.
struct ASProbeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var label: String
        var ends: Date
    }
    init() {}
}

struct LADiagnosticsReport: Sendable {
    let timestamp: Date
    let areActivitiesEnabled: Bool
    let requestSucceeded: Bool
    let requestError: String?
    let probeCountAfter: Int
    let ourTypeCountAfter: Int
    let startedButNotListed: Bool

    var summary: String {
        """
        [LA DIAG] time=\(DiagLog.f(timestamp)) enabled=\(areActivitiesEnabled) \
        request.ok=\(requestSucceeded) error=\(requestError ?? "-") \
        probe.after=\(probeCountAfter) our.after=\(ourTypeCountAfter) \
        startedButNotListed=\(startedButNotListed)
        """
    }
}

enum LADiagnostics {

    /// End any leftover probe activities from prior runs.
    @MainActor
    static func cleanupProbes() async {
        for a in Activity<ASProbeAttributes>.activities {
            let content = ActivityContent(state: a.content.state, staleDate: nil)
            await a.end(content, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
        }
    }

    /// One-shot Live Activity probe (no visible UI unless you have a widget for ASProbeAttributes).
    @MainActor
    static func runSmokeTest() async -> LADiagnosticsReport {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled

        await cleanupProbes()

        var ok = false
        var err: String? = nil

        do {
            let attrs = ASProbeAttributes()
            let state = ASProbeAttributes.ContentState(label: "Probe", ends: Date().addingTimeInterval(120))
            let content = ActivityContent(state: state, staleDate: nil)
            _ = try Activity<ASProbeAttributes>.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
            ok = true
        } catch {
            ok = false
            err = "\(error)"
        }

        // Give the framework a beat to register the request.
        try? await Task.sleep(nanoseconds: 150_000_000)

        let probeAfter = Activity<ASProbeAttributes>.activities.count
        let ourAfter   = Activity<AlarmActivityAttributes>.activities.count

        // Clean up probe(s).
        await cleanupProbes()

        let report = LADiagnosticsReport(
            timestamp: Date(),
            areActivitiesEnabled: enabled,
            requestSucceeded: ok,
            requestError: err,
            probeCountAfter: probeAfter,
            ourTypeCountAfter: ourAfter,
            startedButNotListed: (ok && probeAfter == 0)
        )

        DiagLog.log(report.summary)
        return report
    }

    /// Quick counts/enablement snapshot without creating anything.
    @MainActor
    static func quickSnapshot() {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let probe = Activity<ASProbeAttributes>.activities.count
        let ours  = Activity<AlarmActivityAttributes>.activities.count
        DiagLog.log("[LA SNAP] enabled=\(enabled) probeCount=\(probe) ourCount=\(ours)")
    }

    // MARK: Debug helpers to prove AlarmActivity works end-to-end

    /// Force-start an AlarmActivity for 90s so you can see it running.
    @MainActor
    static func startDebugAlarmActivity() async {
        let ends = Date().addingTimeInterval(90)
        await LiveActivityController.shared.prearmOrUpdate(
            stackID: "DEBUG-STACK",
            stackName: "Debug Stack",
            stepTitle: "Debug Step",
            ends: ends,
            allowSnooze: true,
            alarmID: "debug-\(UUID().uuidString)",
            theme: ThemeMap.payload(for: "Default")
        )
    }

    /// End all AlarmActivities (debug).
    @MainActor
    static func endAllAlarmActivities() async {
        await LiveActivityController.shared.endAll()
    }
}

// MARK: - AlarmKit diagnostics record (persist target times + snooze tap tracking)

@MainActor
enum AKDiag {
    private static func key(_ id: UUID) -> String { "ak.record.\(id.uuidString)" }
    private static func tapKey(_ base: UUID) -> String { "ak.snooze.tap.\(base.uuidString)" }
    private static func expectedKey(_ id: UUID) -> String { "ak.expected.\(id.uuidString)" }

    enum Kind: String, Codable { case step, snooze, test }

    /// One record per scheduled AK alarm (step, snooze, or test).
    struct Record: Codable {
        // Base fields
        var stackName: String
        var stepTitle: String
        var scheduledAt: Date
        var scheduledUptime: TimeInterval
        var targetDate: Date
        var targetUptime: TimeInterval
        var seconds: Int

        // Extended fields
        var kind: Kind?
        var baseID: String?
        var isFirstRun: Bool?
        var minLeadSeconds: Int?
        var allowSnooze: Bool?
        var soundName: String?
        var snoozeMinutes: Int?
        var build: String?
        var source: String?

        // Nominal (desired calendar) target for steps
        var nominalDate: Date?
        var nominalSource: String?
    }

    // Persist/restore a snooze tap moment (for measuring tap→alert)
    private struct Tap: Codable { let wall: Date; let up: TimeInterval }

    static func rememberSnoozeTap(for base: UUID,
                                  wall: Date = Date(),
                                  up: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let data = try? JSONEncoder().encode(Tap(wall: wall, up: up)) {
            UserDefaults.standard.set(data, forKey: tapKey(base))
        }
        DiagLog.log("AK SNOOZE TAPPED base=\(base.uuidString)")
    }

    static func loadSnoozeTap(for base: UUID) -> (Date, TimeInterval)? {
        guard let data = UserDefaults.standard.data(forKey: tapKey(base)),
              let tap = try? JSONDecoder().decode(Tap.self, from: data) else { return nil }
        return (tap.wall, tap.up)
    }

    static func clearSnoozeTap(for base: UUID) {
        UserDefaults.standard.removeObject(forKey: tapKey(base))
    }

    // MARK: Save / Load

    static func save(id: UUID, record: Record) {
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: key(id))
        }

        // Human-readable one-liner with optional shift
        let k = record.kind?.rawValue ?? "step"
        let base = record.baseID ?? "-"
        let lead = record.minLeadSeconds.map(String.init) ?? "-"
        let snoozeMins = record.snoozeMinutes.map(String.init) ?? "-"
        let snd = record.soundName ?? "-"
        let fr = (record.isFirstRun ?? false) ? "1st" : "n"
        var nominal = ""
        if let nd = record.nominalDate {
            let shift = record.targetDate.timeIntervalSince(nd)
            nominal = " nominal=\(DiagLog.f(nd)) shift=\(String(format: "%.3fs", shift))"
        }
        DiagLog.log(
            "AK rec kind=\(k) id=\(id.uuidString) base=\(base) stack=\(record.stackName) step=\(record.stepTitle) " +
            "secs=\(record.seconds) minLead=\(lead) snoozeMins=\(snoozeMins) sound=\(snd) firstRun=\(fr) " +
            "scheduledAt=\(DiagLog.f(record.scheduledAt)) effTarget=\(DiagLog.f(record.targetDate))" + nominal
        )
    }

    static func load(id: UUID) -> Record? {
        guard let data = UserDefaults.standard.data(forKey: key(id)) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    static func remove(id: UUID) { UserDefaults.standard.removeObject(forKey: key(id)) }

    // Expected fire time helpers (for simple fallback delta logging)
    static func markExpected(id: UUID, target: Date) {
        UserDefaults.standard.set(target.timeIntervalSince1970, forKey: expectedKey(id))
    }
    static func loadExpected(id: UUID) -> Date? {
        let ts = UserDefaults.standard.double(forKey: expectedKey(id))
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
    static func clearExpected(id: UUID) {
        UserDefaults.standard.removeObject(forKey: expectedKey(id))
    }

    // MARK: - Convenience helpers

    /// Δ relative to the **effective** timer target.
    static func deltasAtAlert(using rec: Record,
                              nowWall: Date = Date(),
                              nowUp: TimeInterval = ProcessInfo.processInfo.systemUptime) -> (Double, Double) {
        let wallDelta = nowWall.timeIntervalSince(rec.targetDate)
        let upDelta   = nowUp - rec.targetUptime
        return (wallDelta, upDelta)
    }

    /// Δ relative to the **nominal** target, if known.
    static func nominalDeltaAtAlert(using rec: Record,
                                    nowWall: Date = Date()) -> Double? {
        guard let nd = rec.nominalDate else { return nil }
        return nowWall.timeIntervalSince(nd)
    }

    static func markSnoozeChain(base baseID: UUID, snooze newID: UUID, minutes: Int, seconds: Int, target: Date) {
        let upNow = ProcessInfo.processInfo.systemUptime
        DiagLog.log(
            "AK SNOOZE CHAIN base=\(baseID.uuidString) -> id=\(newID.uuidString) mins=\(minutes) secs=\(seconds) " +
            "scheduledAt=\(DiagLog.f(Date())) up=\(String(format: "%.3f", upNow)) effTarget=\(DiagLog.f(target))"
        )
    }

    static func markStopped(id: UUID) {
        DiagLog.log("AK STOP id=\(id.uuidString)")
    }

    // CSV export

    static func csvRow(for id: UUID, rec: Record, alertWall: Date? = nil, alertUp: TimeInterval? = nil) -> String {
        let kind = rec.kind?.rawValue ?? "step"
        let base = rec.baseID ?? ""
        let sound = rec.soundName ?? ""
        let allow = (rec.allowSnooze ?? false) ? "1" : "0"
        let fr = (rec.isFirstRun ?? false) ? "1" : "0"
        let lead = rec.minLeadSeconds.map(String.init) ?? ""
        let snoozeMins = rec.snoozeMinutes.map(String.init) ?? ""
        let build = rec.build ?? ""
        let source = rec.source ?? ""
        let nominal = rec.nominalDate.map(DiagLog.f) ?? ""

        var wallEffΔ = ""
        var upΔ = ""
        var wallNomΔ = ""
        if let aw = alertWall, let au = alertUp {
            let (w, u) = deltasAtAlert(using: rec, nowWall: aw, nowUp: au)
            wallEffΔ = String(format: "%.3f", w)
            upΔ = String(format: "%.3f", u)
            if let nd = rec.nominalDate {
                wallNomΔ = String(format: "%.3f", aw.timeIntervalSince(nd))
            }
        }

        let shift = rec.nominalDate.map { rec.targetDate.timeIntervalSince($0) }.map { String(format: "%.3f", $0) } ?? ""

        return [
            id.uuidString,
            kind,
            base,
            rec.stackName,
            rec.stepTitle,
            DiagLog.f(rec.scheduledAt),
            String(format: "%.3f", rec.scheduledUptime),
            DiagLog.f(rec.targetDate),
            String(format: "%.3f", rec.targetUptime),
            "\(rec.seconds)",
            lead,
            snoozeMins,
            sound,
            allow,
            fr,
            build,
            source,
            nominal,
            shift,
            wallEffΔ,
            wallNomΔ,
            upΔ
        ].joined(separator: ",")
    }

    static func exportCSV() -> String {
        let mirror = UserDefaults.standard.dictionaryRepresentation()
        let prefix = "ak.record."
        let keys = mirror.keys.filter { $0.hasPrefix(prefix) }
        var rows: [String] = []
        rows.append([
            "id","kind","baseID","stackName","stepTitle",
            "scheduledAtLocal","scheduledUptime",
            "effectiveTargetLocal","effectiveTargetUptime","seconds",
            "minLead","snoozeMinutes","sound","allowSnooze","firstRun","build","source",
            "nominalTargetLocal","effectiveMinusNominalShift",
            "alertEffDelta","alertNominalDelta","alertUpDelta"
        ].joined(separator: ","))

        for k in keys.sorted() {
            let idStr = String(k.dropFirst(prefix.count))
            guard let id = UUID(uuidString: idStr),
                  let rec = load(id: id) else { continue }
            rows.append(csvRow(for: id, rec: rec))
        }
        return rows.joined(separator: "\n")
    }
}

// MARK: - UI: selectable/copyable diagnostics viewer

struct DiagnosticsLogView: View {
    @State private var lines: [String] = DiagLog.read()
    @State private var csv: String = ""
    private var joined: String { lines.joined(separator: "\n\n") }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(joined.isEmpty ? "No entries yet." : joined)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
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

                if csv.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CSV Preview (AK Records)")
                            .font(.system(.headline, design: .rounded))
                        ScrollView(.horizontal) {
                            Text(csv)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top)
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Clear") {
                    DiagLog.clear()
                    lines = []
                    csv = ""
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Copy Log") { UIPasteboard.general.string = joined }
                ShareLink(item: joined) { Text("Share Log") }
                Button("Refresh") { refresh(withAudits: true) }
                Menu("AK Export") {
                    Button("Copy CSV") {
                        csv = AKDiag.exportCSV()
                        UIPasteboard.general.string = csv
                    }
                    Button("Refresh CSV Preview") {
                        csv = AKDiag.exportCSV()
                    }
                }
                Menu("LA Tools") {
                    Button("LA Snapshot") {
                        Task { @MainActor in
                            LADiagnostics.quickSnapshot()
                            lines = DiagLog.read()
                        }
                    }
                    Button("LA Smoke Test") {
                        Task { @MainActor in
                            _ = await LADiagnostics.runSmokeTest()
                            lines = DiagLog.read()
                        }
                    }
                    Divider()
                    Button("Start AlarmActivity (Debug, +90s)") {
                        Task { @MainActor in
                            await LADiagnostics.startDebugAlarmActivity()
                            lines = DiagLog.read()
                        }
                    }
                    Button("End All AlarmActivities") {
                        Task { @MainActor in
                            await LADiagnostics.endAllAlarmActivities()
                            lines = DiagLog.read()
                        }
                    }
                }
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
