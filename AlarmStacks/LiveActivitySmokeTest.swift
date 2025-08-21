//
//  LiveActivitySmokeTest.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//

import Foundation
import ActivityKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum LiveActivitySmokeTest {

    /// Call this freely (e.g. from `.onAppear` or when the app becomes active).
    static func kick() {
        #if DEBUG
        Task { await run() }
        #endif
    }

    private static func runChecks() -> Bool {
        DiagLog.log("[LA][SMOKE] kick")
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            DiagLog.log("[LA][SMOKE] areActivitiesEnabled == false — abort")
            return false
        }
        #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom != .phone {
            DiagLog.log("[LA][SMOKE] Not an iPhone — abort")
            return false
        }
        #if targetEnvironment(simulator)
        DiagLog.log("[LA][SMOKE] Simulator — Live Activities don’t render")
        return false
        #endif
        #endif
        return true
    }

    private static func makeContent() -> ActivityContent<AlarmActivityAttributes.ContentState> {
        let ends = Date().addingTimeInterval(120) // 2 minutes from now
        let state = AlarmActivityAttributes.ContentState(
            stackName: "SMOKE",
            stepTitle: "Test",
            ends: ends,
            allowSnooze: false,
            alarmID: "",
            firedAt: nil,
            accentHex: "#FF006E"
        )
        return ActivityContent(state: state, staleDate: nil)
    }

    private static func existing() -> Activity<AlarmActivityAttributes>? {
        Activity<AlarmActivityAttributes>.activities.first
    }

    private static func endIfPast(_ activity: Activity<AlarmActivityAttributes>) async {
        let st = activity.content.state
        if st.ends <= Date() {
            let content = ActivityContent(state: st, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            DiagLog.log("[LA][SMOKE] ended stale id=\(activity.id)")
        }
    }

    private static func run() async {
        guard runChecks() else { return }

        // If there’s one already, update it; otherwise request a new one.
        if let a = existing() {
            await endIfPast(a)
            let content = makeContent()
            DiagLog.log("[LA][SMOKE] update → ends=\(content.state.ends)")
            await a.update(content)
            DiagLog.log("[LA][SMOKE] update OK id=\(a.id)")
            return
        }

        do {
            let content = makeContent()
            let a = try Activity.request(
                attributes: AlarmActivityAttributes(),
                content: content,
                pushType: nil
            )
            DiagLog.log("[LA][SMOKE] request OK id=\(a.id) ends=\(content.state.ends)")
        } catch {
            DiagLog.log("[LA][SMOKE] request ERROR \(error)")
        }
    }
}
