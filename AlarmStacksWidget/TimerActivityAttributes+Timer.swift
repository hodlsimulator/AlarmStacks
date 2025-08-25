//
//  TimerActivityAttributes+Timer.swift
//  AlarmStacks
//
//  Created by . . on 8/25/25.
//

import Foundation
import ActivityKit

// Widget target copy of the attributes used by the timer Live Activity.
// Keep this in sync with the app target definition.
public struct TimerActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable {
        public var endDate: Date?
        public var isPaused: Bool
        public var remainingSeconds: Int

        public init(endDate: Date?, isPaused: Bool, remainingSeconds: Int) {
            self.endDate = endDate
            self.isPaused = isPaused
            self.remainingSeconds = remainingSeconds
        }
    }

    public var theme: String
    public var title: String

    public init(theme: String, title: String) {
        self.theme = theme
        self.title = title
    }
}
