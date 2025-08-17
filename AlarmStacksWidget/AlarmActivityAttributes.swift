//
//  AlarmActivityAttributes.swift
//  AlarmStacksWidget
//
//  Created by . . on 8/17/25.
//
//  AlarmActivityAttributes.swift
//  AlarmStacks (shared with AlarmStacksWidget)
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct AlarmActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stackName: String
        var stepTitle: String
        var ends: Date
        var allowSnooze: Bool
        var alarmID: String
        init(stackName: String, stepTitle: String, ends: Date, allowSnooze: Bool, alarmID: String) {
            self.stackName = stackName
            self.stepTitle = stepTitle
            self.ends = ends
            self.allowSnooze = allowSnooze
            self.alarmID = alarmID
        }
    }
    init() {}
}
#endif
