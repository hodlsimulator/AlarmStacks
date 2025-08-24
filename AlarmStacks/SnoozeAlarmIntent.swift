//
//  SnoozeAlarmIntent.swift
//  AlarmStacks
//
//  Created by . . on 8/24/25.
//

import Foundation
import AppIntents
import AlarmKit
import SwiftUI

/// Minimal Snooze intent used when scheduling alarms (passed as `secondaryIntent`).
/// The heavy lifting for snoozing is handled elsewhere (e.g., scheduler/intent handlers).
/// This type just needs to exist and conform to `AppIntent & LiveActivityIntent` so
/// callers like `AlarmKitScheduler` can reference `SnoozeAlarmIntent(alarmID:)`.
struct SnoozeAlarmIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Snooze Alarm" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() { self.alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        // Intentionally no-op here; actual snooze behavior is driven by your
        // scheduler/intent pipeline. Returning success is sufficient to satisfy
        // AppIntents execution when invoked directly.
        return .result()
    }
}
