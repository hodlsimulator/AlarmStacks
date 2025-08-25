//
//  TimerLA.swift
//  AlarmStacks
//
//  Created by . . on 8/25/25.
//

import Foundation
import ActivityKit

enum TimerLA {
    private static var activity: Activity<TimerActivityAttributes>?

    static func start(endDate: Date, paused: Bool, title: String, theme: String) {
        let attrs = TimerActivityAttributes(theme: theme, title: title)
        let state = TimerActivityAttributes.ContentState(
            endDate: paused ? nil : endDate,
            isPaused: paused,
            remainingSeconds: Int(max(0, endDate.timeIntervalSinceNow))
        )

        if let a = activity {
            // update is async (not throwing)
            Task { await a.update(.init(state: state, staleDate: nil)) }
        } else {
            // request throws (synchronous)
            do {
                activity = try Activity<TimerActivityAttributes>.request(
                    attributes: attrs,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                // ignore request failure
            }
        }
    }

    static func update(remaining: Int, paused: Bool, title: String, theme: String) {
        let end = paused ? nil : Date().addingTimeInterval(TimeInterval(remaining))
        let state = TimerActivityAttributes.ContentState(endDate: end, isPaused: paused, remainingSeconds: remaining)

        if let a = activity {
            Task { await a.update(.init(state: state, staleDate: nil)) }
        } else {
            // Start lazily if not present
            start(endDate: Date().addingTimeInterval(TimeInterval(remaining)),
                  paused: paused, title: title, theme: theme)
        }
    }

    static func end() {
        guard let a = activity else { return }
        Task {
            await a.end(nil, dismissalPolicy: .immediate)
            activity = nil
        }
    }
}

// MARK: - Attributes (app target copy)

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
