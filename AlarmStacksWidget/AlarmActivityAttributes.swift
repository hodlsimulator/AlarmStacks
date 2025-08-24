//
//  AlarmActivityAttributes.swift
//  AlarmStacksWidget
//  Created by . . on 8/17/25.
//

import Foundation
import ActivityKit
import SwiftUI

public struct AlarmActivityAttributes: ActivityAttributes {
    // MARK: - Fixed attributes (one per stack / activity)
    /// Stable identifier for the stack this activity represents.
    public var stackID: String

    /// Dedupe key used by LiveActivityStartGate.
    /// We reuse `stackID` so existing call sites don’t need to change.
    public var alarmKey: String? { stackID }

    public init(stackID: String) {
        self.stackID = stackID
    }

    // MARK: - Dynamic content state
    public struct ContentState: Codable, Hashable {
        public var stackName: String
        public var stepTitle: String
        /// Scheduled ring time (effective for timers / snoozes)
        public var ends: Date
        public var allowSnooze: Bool
        /// AlarmKit UUID string if available
        public var alarmID: String
        /// Actual ring moment (set when alerting)
        public var firedAt: Date?

        /// Theme payload (Hashable & Codable)
        public var theme: ThemePayload

        public init(stackName: String,
                    stepTitle: String,
                    ends: Date,
                    allowSnooze: Bool,
                    alarmID: String,
                    firedAt: Date? = nil,
                    theme: ThemePayload = ThemeMap.payload(for: "Default")) {
            self.stackName = stackName
            self.stepTitle = stepTitle
            self.ends = ends
            self.allowSnooze = allowSnooze
            self.alarmID = alarmID
            self.firedAt = firedAt
            self.theme = theme
        }

        private enum CodingKeys: String, CodingKey {
            case stackName, stepTitle, ends, allowSnooze, alarmID, firedAt, theme
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.stackName = try c.decode(String.self, forKey: .stackName)
            self.stepTitle = try c.decode(String.self, forKey: .stepTitle)
            self.ends = try c.decode(Date.self, forKey: .ends)
            self.allowSnooze = try c.decode(Bool.self, forKey: .allowSnooze)
            self.alarmID = try c.decode(String.self, forKey: .alarmID)
            self.firedAt = try c.decodeIfPresent(Date.self, forKey: .firedAt)
            self.theme = (try? c.decode(ThemePayload.self, forKey: .theme)) ?? ThemeMap.payload(for: "Default")
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(stackName, forKey: .stackName)
            try c.encode(stepTitle, forKey: .stepTitle)
            try c.encode(ends, forKey: .ends)
            try c.encode(allowSnooze, forKey: .allowSnooze)
            try c.encode(alarmID, forKey: .alarmID)
            try c.encodeIfPresent(firedAt, forKey: .firedAt)
            try c.encode(theme, forKey: .theme)
        }
    }
}
