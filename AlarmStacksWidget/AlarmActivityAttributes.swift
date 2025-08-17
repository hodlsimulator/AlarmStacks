//
//  AlarmActivityAttributes.swift
//  AlarmStacks (shared with AlarmStacksWidget)
//  Created by . . on 8/17/25.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
public struct AlarmActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var stackName: String
        public var stepTitle: String
        public var ends: Date
        public var allowSnooze: Bool
        public var alarmID: String
        public init(stackName: String, stepTitle: String, ends: Date, allowSnooze: Bool, alarmID: String) {
            self.stackName = stackName
            self.stepTitle = stepTitle
            self.ends = ends
            self.allowSnooze = allowSnooze
            self.alarmID = alarmID
        }
    }
    public init() {}
}
#endif
