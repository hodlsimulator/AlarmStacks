//
//  AlarmActivityAttributes.swift
//  AlarmStacksWidget
//  Created by . . on 8/17/25.
//

import Foundation
import ActivityKit
import SwiftUI

public struct AlarmActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var stackName: String
        public var stepTitle: String
        public var ends: Date               // scheduled ring time
        public var allowSnooze: Bool
        public var alarmID: String          // AlarmKit UUID string if available
        public var firedAt: Date?           // actual ring moment (set when alerting)
        public init(stackName: String,
                    stepTitle: String,
                    ends: Date,
                    allowSnooze: Bool,
                    alarmID: String,
                    firedAt: Date? = nil) {
            self.stackName = stackName
            self.stepTitle = stepTitle
            self.ends = ends
            self.allowSnooze = allowSnooze
            self.alarmID = alarmID
            self.firedAt = firedAt
        }
    }
    public init() { }
}
