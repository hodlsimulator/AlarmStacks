//
//  AlarmController.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import Combine
#if canImport(AlarmKit)
import AlarmKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AlarmController: ObservableObject {
    static let shared = AlarmController()

    #if canImport(AlarmKit)
    @Published private(set) var alertingAlarm: Alarm?
    @Published private(set) var lastSnapshot: [Alarm] = []
    private let manager = AlarmManager.shared
    private var observerTask: Task<Void, Never>?
    #endif

    // MARK: - Authorization

    func ensureAuthorised() async throws {
        #if canImport(AlarmKit)
        switch manager.authorizationState {
        case .authorized: break
        case .notDetermined: _ = try await manager.requestAuthorization()
        case .denied:
            throw NSError(
                domain: "AlarmStacks",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Alarm permission denied in Settings."]
            )
        @unknown default: break
        }
        #endif
    }

    // MARK: - Observing AlarmKit

    func startObserversIfNeeded() {
        #if canImport(AlarmKit)
        guard observerTask == nil else { return }

        observerTask = Task { [weak self] in
            guard let self else { return }

            for await snapshot in manager.alarmUpdates {
                await MainActor.run {
                    self.lastSnapshot = snapshot

                    if let a = snapshot.first(where: { $0.state == .alerting }) {
                        self.alertingAlarm = a

                        // --- Diagnostics ---
                        let env   = AppEnv.snapshot()
                        let now   = Date()
                        let upNow = ProcessInfo.processInfo.systemUptime

                        let key = "ak.expected.\(a.id.uuidString)"
                        let ts  = UserDefaults.standard.double(forKey: key)
                        if ts > 0 {
                            let expectedEff = Date(timeIntervalSince1970: ts)

                            if let rec = AKDiag.load(id: a.id) {
                                // Effective (timer) deltas
                                let (wallEffΔ, upΔ) = AKDiag.deltasAtAlert(using: rec, nowWall: now, nowUp: upNow)

                                // Nominal delta + shift (if known)
                                var nominalPart = ""
                                if let wallNomΔ = AKDiag.nominalDeltaAtAlert(using: rec, nowWall: now),
                                   let nd = rec.nominalDate {
                                    let shift = rec.targetDate.timeIntervalSince(nd)
                                    nominalPart = String(
                                        format: " nomΔ=%.3fs shift=%.3fs nominal=%@",
                                        wallNomΔ, shift, DiagLog.f(nd)
                                    )
                                }

                                // Snooze set vs actual + signed delta (positive = early, negative = late)
                                var snoozeDetail = ""
                                if rec.kind == .snooze, let baseStr = rec.baseID, let baseUUID = UUID(uuidString: baseStr) {
                                    let setSeconds = Double(rec.seconds)

                                    if let (tapWall, tapUp) = AKDiag.loadSnoozeTap(for: baseUUID) {
                                        let tapWallΔ   = now.timeIntervalSince(tapWall)
                                        let tapUpΔ     = upNow - tapUp
                                        let tapDeltaVsSet = setSeconds - tapWallΔ   // + = early, - = late

                                        let schedWallΔ = now.timeIntervalSince(rec.scheduledAt)
                                        let schedUpΔ   = upNow - rec.scheduledUptime
                                        let schedDeltaVsSet = setSeconds - schedWallΔ

                                        snoozeDetail = String(
                                            format: " snooze{set=%ds tap→alert=%.3fs ΔvsSet=%+.3fs up=%.3f schedule→alert=%.3fs ΔvsSet=%+.3fs up=%.3f}",
                                            rec.seconds, tapWallΔ, tapDeltaVsSet, tapUpΔ, schedWallΔ, schedDeltaVsSet, schedUpΔ
                                        )
                                        AKDiag.clearSnoozeTap(for: baseUUID)
                                    } else {
                                        let schedWallΔ = now.timeIntervalSince(rec.scheduledAt)
                                        let schedUpΔ   = upNow - rec.scheduledUptime
                                        let schedDeltaVsSet = setSeconds - schedWallΔ

                                        snoozeDetail = String(
                                            format: " snooze{set=%ds schedule→alert=%.3fs ΔvsSet=%+.3fs up=%.3f}",
                                            rec.seconds, schedWallΔ, schedDeltaVsSet, schedUpΔ
                                        )
                                    }
                                }

                                DiagLog.log(String(
                                    format: "AK alerting id=%@ env={%@} effΔ=%.3fs upΔ=%.3fs effTarget=%@%@%@",
                                    a.id.uuidString,
                                    env,
                                    wallEffΔ,
                                    upΔ,
                                    DiagLog.f(rec.targetDate),
                                    nominalPart,
                                    snoozeDetail
                                ))

                                AKDiag.remove(id: a.id)
                            } else {
                                // Fallback: we only know the effective target via expected key
                                let wallEffΔ = now.timeIntervalSince(expectedEff)
                                DiagLog.log(String(
                                    format: "AK alerting id=%@ env={%@} effΔ=%.3fs effTarget=%@",
                                    a.id.uuidString, env, wallEffΔ, DiagLog.f(expectedEff)
                                ))
                            }
                            UserDefaults.standard.removeObject(forKey: key)
                        } else {
                            DiagLog.log("AK alerting id=\(a.id.uuidString) env={\(env)} (no expected fire time recorded)")
                        }
                        // -----------------------------------------

                        // 🔔 Live Activity: prefer stack-aware hook; fallback to generic mark if unknown.
                        let sid = UserDefaults.standard.string(forKey: "ak.stackID.\(a.id.uuidString)") ?? ""
                        if sid.isEmpty {
                            Task { LiveActivityManager.markFiredNow() }
                        } else {
                            self.la_onAKAlerting(stackID: sid, alarmID: a.id.uuidString)
                        }
                    } else {
                        self.alertingAlarm = nil
                    }
                }
            }
        }
        #endif
    }

    func cancelObservers() {
        #if canImport(AlarmKit)
        observerTask?.cancel()
        observerTask = nil
        #endif
    }

    // MARK: - Controls

    func stop(_ id: UUID) {
        #if canImport(AlarmKit)
        try? manager.stop(id: id)
        AKDiag.markStopped(id: id)

        // 🔔 Live Activity end for the owning stack (if we can resolve it)
        let sid = UserDefaults.standard.string(forKey: "ak.stackID.\(id.uuidString)") ?? ""
        if sid.isEmpty == false {
            la_onAKStop(stackID: sid)
        }
        #endif
    }

    func snooze(_ id: UUID) {
        #if canImport(AlarmKit)
        // Capture the tap moment (for tap→alert measurement)
        AKDiag.rememberSnoozeTap(for: id)

        // Silence the current ring immediately.
        try? manager.stop(id: id)

        // Read the per-alarm snooze settings we persisted when scheduling.
        let ud = UserDefaults.standard
        let minutes   = max(1, ud.integer(forKey: "ak.snoozeMinutes.\(id.uuidString)"))
        let stackName = ud.string(forKey: "ak.stackName.\(id.uuidString)") ?? "Alarm"
        let stepTitle = ud.string(forKey: "ak.stepTitle.\(id.uuidString)") ?? "Snoozed"

        Task {
            _ = await AlarmKitScheduler.shared.scheduleSnooze(
                baseAlarmID: id,
                stackName: stackName,
                stepTitle: stepTitle,
                minutes: minutes
            )
        }
        #endif
    }

    // MARK: - Diagnostics

    func auditAKNow() {
        #if canImport(AlarmKit)
        let counts  = Dictionary(grouping: lastSnapshot, by: { $0.state }).mapValues { $0.count }
        let summary = counts
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined()
            .replacingOccurrences(of: "=", with: "=")
            .replacingOccurrences(of: ",", with: " ")
        DiagLog.log("AK snapshot size=\(lastSnapshot.count) states{\(summary)} env={\(AppEnv.snapshot())}")
        #endif
    }
}
