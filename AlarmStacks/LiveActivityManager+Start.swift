//
//  LiveActivityManager+Start.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

extension LiveActivityManager {

    /// Create or update a Live Activity to show the *next* step for `stack`.
    /// If the next step is far in the future, we *avoid* creating/updating to prevent the “in 23 hours” flash.
    @MainActor
    static func start(for stack: Stack, calendar: Calendar) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Compute preview of the next step using the same logic as scheduling.
        guard let preview = nextPreview(for: stack, calendar: calendar) else {
            await end(forStackID: stack.id.uuidString)
            return
        }

        // Hard guard: don’t show far-future times on creation.
        // (Scheduler will call this again once near-term reschedule lands.)
        if preview.ends.timeIntervalSinceNow > 90 * 60 { // 90 minutes
            await end(forStackID: stack.id.uuidString)
            return
        }

        // Build attributes + state
        let attrs = LAAttributes(stackID: stack.id.uuidString)
        let themeName = UserDefaults(suiteName: AppGroups.main)?
            .string(forKey: "themeName") ?? "Default"
        let theme = ThemeMap.payload(for: themeName)

        let state = LAAttributes.ContentState(
            stackName: stack.name,
            stepTitle: preview.stepTitle,
            ends: preview.ends,
            allowSnooze: preview.allowSnooze,
            alarmID: preview.alarmID,
            firedAt: nil,
            theme: theme
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let existing = Activity<LAAttributes>.activities.first(where: { $0.attributes.stackID == attrs.stackID }) {
            await existing.update(content) // iOS 16.2+ API
        } else {
            // New request with small retry for transient “visibility” conditions (Focus/lock transitions etc.)
            let act = await requestWithRetry(attributes: attrs, content: content)
            if act == nil {
                // Defer a retry to the first lock/background we observe.
                LiveActivityVisibilityRetry.registerPending(stackID: attrs.stackID)
                DiagLog.log("LA request failed (visibility); queued for background retry stack=\(attrs.stackID)")
            }
        }
        #endif
    }

    /// Determine the *next* step’s display info. First enabled step with a valid time.
    private static func nextPreview(for stack: Stack, calendar: Calendar)
    -> (stepTitle: String, ends: Date, allowSnooze: Bool, alarmID: String)? {
        var last = Date()
        for step in stack.sortedSteps where step.isEnabled {
            let ends: Date?
            switch step.kind {
            case .fixedTime:
                ends = try? step.nextFireDate(basedOn: Date(), calendar: calendar)
            case .timer, .relativeToPrev:
                ends = try? step.nextFireDate(basedOn: last, calendar: calendar)
            }
            guard let fireDate = ends else { continue }
            last = fireDate

            // Use the same id shape you use for notifications so LA & UN feel consistent
            let alarmID = "stack-\(stack.id.uuidString)-step-\(step.id.uuidString)-0"
            return (stepTitle: step.title, ends: fireDate, allowSnooze: step.allowSnooze, alarmID: alarmID)
        }
        return nil
    }

    // MARK: - Transient request retry

    /// Retries Activity.request a couple of times to ride out transient “visibility” failures.
    @MainActor
    private static func requestWithRetry(attributes: LAAttributes,
                                         content: ActivityContent<LAAttributes.ContentState>,
                                         retries: Int = 2,
                                         delayNs: UInt64 = 250_000_000) async -> Activity<LAAttributes>? {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return nil }
        var attempt = 0
        while true {
            do {
                let act = try Activity<LAAttributes>.request(attributes: attributes, content: content, pushType: nil)
                return act
            } catch {
                attempt += 1
                let desc = (error as NSError).localizedDescription.lowercased()
                let isVisibilityLike = desc.contains("visibility") || desc.contains("not visible") || desc.contains("lock screen")
                if attempt > retries || !isVisibilityLike {
                    DiagLog.log("LA request failed: \(desc) attempts=\(attempt)")
                    return nil
                }
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }
        #else
        return nil
        #endif
    }
}
