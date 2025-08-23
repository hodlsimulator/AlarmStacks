//
//  ScheduleRevision+MainActor.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//
//  Purpose:
//  - Ensure all revision bumps happen on the main actor to avoid concurrency warnings.
//  - This assumes you already have `ScheduleRevision.bump(String)` defined elsewhere.
//

import Foundation

extension ScheduleRevision {
    @MainActor
    static func bumpOnMain(_ reason: String = "") {
        bump(reason)
    }
}
