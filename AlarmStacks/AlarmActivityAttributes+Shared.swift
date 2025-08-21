//
//  AlarmActivityAttributes+Shared.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//

import Foundation
import ActivityKit

public struct AlarmActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var stackName: String
        public var stepTitle: String
        public var ends: Date
        public var allowSnooze: Bool
        public var alarmID: String
        public var firedAt: Date?
        public var accentHex: String

        public init(
            stackName: String,
            stepTitle: String,
            ends: Date,
            allowSnooze: Bool,
            alarmID: String,
            firedAt: Date? = nil,
            accentHex: String
        ) {
            self.stackName = stackName
            self.stepTitle = stepTitle
            self.ends = ends
            self.allowSnooze = allowSnooze
            self.alarmID = alarmID
            self.firedAt = firedAt
            self.accentHex = accentHex
        }
    }

    public init() {}
}
