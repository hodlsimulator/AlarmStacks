//
//  AlarmKitScheduler.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

#if canImport(AlarmKit)
import Foundation
import SwiftData
import AlarmKit

@MainActor
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()
    private let fallback = UserNotificationScheduler.shared

    init() {}

    func requestAuthorizationIfNeeded() async throws {
        // Until real AlarmKit auth is wired, forward to notifications auth.
        try await fallback.requestAuthorizationIfNeeded()
    }

    func schedule(stack: Stack, calendar: Calendar = .current) async throws -> [String] {
        // Forward to fallback for now.
        try await fallback.schedule(stack: stack, calendar: calendar)
    }

    func cancelAll(for stack: Stack) async {
        await fallback.cancelAll(for: stack)
    }

    func rescheduleAll(stacks: [Stack], calendar: Calendar = .current) async {
        await fallback.rescheduleAll(stacks: stacks, calendar: calendar)
    }
}
#endif
