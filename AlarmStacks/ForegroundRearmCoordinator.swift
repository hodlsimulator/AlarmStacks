//
//  ForegroundRearmCoordinator.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import SwiftUI
import SwiftData
import UserNotifications

/// Invisible helper that re-arms ALL armed stacks only when the user returns
/// from Settings after tapping our explainer's button. It never runs otherwise.
/// Also: ends the Live Activity if its scheduled time has passed when the app
/// returns to the foreground (prevents stale bubbles).
struct ForegroundRearmCoordinator: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Color.clear
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await LiveActivityManager.endIfExpired()
                        await auditUN() // log what actually happened while we were away
                        if SettingsRearmGate.consume() {
                            await rearmAllArmed()
                        }
                    }
                }
            }
    }

    @MainActor
    private func rearmAllArmed() async {
        let stacks = (try? modelContext.fetch(FetchDescriptor<Stack>())) ?? []
        let armed = stacks.filter { $0.isArmed }
        guard !armed.isEmpty else { return }
        await AlarmScheduler.shared.rescheduleAll(stacks: armed, calendar: .current)
    }

    private func auditUN() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()

        DiagLog.log("UN audit pending=\(pending.count) delivered=\(delivered.count)")

        for d in delivered {
            let id = d.request.identifier
            if let ts = UserDefaults.standard.object(forKey: "un.expected.\(id)") as? Double {
                let expected = Date(timeIntervalSince1970: ts)
                let delta = Date().timeIntervalSince(expected)
                DiagLog.log(String(format: "UN delivered id=%@ delta=%.1fs expected=%@", id, delta, expected as CVarArg))
                UserDefaults.standard.removeObject(forKey: "un.expected.\(id)")
            }
        }

        // If anything is still pending well after expected, note it.
        let now = Date()
        for p in pending {
            let id = p.identifier
            if let ts = UserDefaults.standard.object(forKey: "un.expected.\(id)") as? Double {
                let expected = Date(timeIntervalSince1970: ts)
                if now.timeIntervalSince(expected) > 20 {
                    DiagLog.log("UN pending past expected id=\(id) by ~\(Int(now.timeIntervalSince(expected)))s")
                }
            }
        }
    }
}
