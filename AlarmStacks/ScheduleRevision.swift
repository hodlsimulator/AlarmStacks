//
//  ScheduleRevision.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//
//  Shared revision counter (App Group). Bump this anywhere the chain changes
//  (schedule, snooze, enable/disable, theme change) to trigger a widget reload
//  and give us searchable logs.
//

import Foundation
import WidgetKit

enum ScheduleRevision {
    private static let appGroupID = "group.com.hodlsimulator.alarmstacks"
    private static let key = "ak.schedule.revision"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Read current revision (0 if never set).
    static func current() -> Int {
        defaults.integer(forKey: key)
    }

    /// Atomically increment the revision and reload widget timelines.
    @discardableResult
    static func bump(_ reason: String) -> Int {
        let next = defaults.integer(forKey: key) &+ 1
        defaults.set(next, forKey: key)
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        print("[WIDGET] reload reason=\(reason) rev=\(next)")
        return next
    }
}
