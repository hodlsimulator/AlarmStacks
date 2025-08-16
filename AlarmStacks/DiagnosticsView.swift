//
//  DiagnosticsView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

@MainActor
struct DiagnosticsView: View {
    // Compile-time: is AlarmKit in this build?
    private let alarmKitAvailable: Bool = {
        #if canImport(AlarmKit)
        return true
        #else
        return false
        #endif
    }()

    @State private var akAuthorization: String = "—"
    @State private var unAuthorization: String = "—"
    @State private var unDetails: [(String, String)] = []

    // A private “test” stack we won’t insert into SwiftData. We schedule against it
    // so we can cancel without touching your real stacks.
    @State private var testStack = Stack(name: "Diagnostics Test")
    @State private var scheduledAt: Date?
    @State private var lastResult: String = ""

    var body: some View {
        List {
            Section("Scheduler backend") {
                row("Build has AlarmKit", alarmKitAvailable ? "Yes" : "No")
                #if canImport(AlarmKit)
                row("Alias in use", "AlarmScheduler → AppAlarmKitScheduler")
                #else
                row("Alias in use", "AlarmScheduler → LocalNotificationScheduler (UN)")
                #endif
            }

            Section("AlarmKit") {
                row("Authorisation", akAuthorization)
                HStack {
                    Button("Request/Check Authorisation") { Task { await refreshStates(requestAK: true) } }
                    if alarmKitAvailable {
                        Button("Open Settings") { openAppSettings() }
                    }
                }
                .buttonStyle(.bordered)
            }

            Section("Notifications (UN)") {
                row("Authorisation", unAuthorization)
                ForEach(unDetails, id: \.0) { (k, v) in row(k, v) }
                HStack {
                    Button("Open Settings") { openAppSettings() }
                    Button("Refresh") { Task { await refreshStates(requestAK: false) } }
                }
                .buttonStyle(.bordered)
            }

            Section("Quick tests") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("10-second test")
                        .font(.headline)
                    Text("Tap Start, then switch to another app. If AlarmKit is active + authorised you should get a proper alarm alert. If you only feel a short buzz (or nothing) you’re on the UN fallback or banners/sounds are disabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        Task { await startTenSecondTest() }
                    } label: {
                        Label("Start (10s)", systemImage: "timer")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        Task { await cancelTenSecondTest() }
                    } label: {
                        Label("Cancel Test", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if let t = scheduledAt {
                    row("Scheduled at", DateFormatter.localizedString(from: t, dateStyle: .none, timeStyle: .medium))
                }
                if !lastResult.isEmpty {
                    row("Last result", lastResult)
                }
            }
        }
        .navigationTitle("Alarm Diagnostics")
        .task { await refreshStates(requestAK: false) }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    // MARK: - State / Permissions

    private func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not determined"
        case .denied:        return "Denied"
        case .authorized:    return "Authorized"
        case .provisional:   return "Provisional"
        case .ephemeral:     return "Ephemeral"
        @unknown default:    return "Unknown"
        }
    }

    private func describe(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled:      return "Enabled"
        case .disabled:     return "Disabled"
        case .notSupported: return "Not supported"
        @unknown default:   return "Unknown"
        }
    }

    private func describe(_ style: UNAlertStyle) -> String {
        switch style {
        case .none:    return "None"
        case .banner:  return "Banners"
        case .alert:   return "Alerts"
        @unknown default: return "Unknown"
        }
    }

    private func refreshUN() async {
        let center = UNUserNotificationCenter.current()
        let s = await center.notificationSettings()
        unAuthorization = describe(s.authorizationStatus)

        var rows: [(String, String)] = []
        rows.append(("Lock Screen", describe(s.lockScreenSetting)))
        rows.append(("Notification Centre", describe(s.notificationCenterSetting)))
        rows.append(("Badge", describe(s.badgeSetting)))
        rows.append(("Sound", describe(s.soundSetting)))
        if #available(iOS 15.0, *) {
            rows.append(("Critical Alerts", describe(s.criticalAlertSetting)))
            rows.append(("Time Sensitive", describe(s.timeSensitiveSetting)))
        }
        rows.append(("Alert Style", describe(s.alertStyle))) // Maps to banners/alerts/none

        unDetails = rows
    }

    private func refreshAK(requestAK: Bool) async {
        #if canImport(AlarmKit)
        let mgr = AlarmManager.shared
        if requestAK && mgr.authorizationState == .notDetermined {
            do { _ = try await mgr.requestAuthorization() } catch { /* ignore for display */ }
        }
        switch mgr.authorizationState {
        case .authorized:   akAuthorization = "Authorized"
        case .denied:       akAuthorization = "Denied"
        case .notDetermined:akAuthorization = "Not determined"
        @unknown default:   akAuthorization = "Unknown"
        }
        #else
        akAuthorization = "Unavailable in this build"
        #endif
    }

    private func refreshStates(requestAK: Bool) async {
        await refreshAK(requestAK: requestAK)
        await refreshUN()
    }

    // MARK: - Tests

    private func startTenSecondTest() async {
        // Fresh “test” step each time so identifiers change.
        let step = Step(title: "Diagnostics 10s", kind: .timer, order: 0,
                        durationSeconds: 10, allowSnooze: true, snoozeMinutes: 9, stack: testStack)
        testStack.steps = [step]

        do {
            _ = try await AlarmScheduler.shared.schedule(stack: testStack, calendar: .current)
            scheduledAt = .now
            #if canImport(AlarmKit)
            lastResult = (AlarmManager.shared.authorizationState == .authorized) ? "Scheduled via AlarmKit (expected)" : "Scheduled via UN fallback (AK denied)"
            #else
            lastResult = "Scheduled via UN fallback (no AlarmKit in build)"
            #endif
        } catch {
            lastResult = "Scheduling error: \(error.localizedDescription)"
        }
        await refreshStates(requestAK: false)
    }

    private func cancelTenSecondTest() async {
        await AlarmScheduler.shared.cancelAll(for: testStack)
        lastResult = "Cancelled pending test requests"
    }
}
