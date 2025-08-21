//
//  AlarmSchedulerFacade.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation

// MARK: - Optional capability (no AlarmKit import needed here)
@MainActor
protocol AlarmSnoozing: AnyObject {
    /// Centralised AK path: stop current ring, schedule snooze, shift chain.
    @discardableResult
    func snoozeFromIntent(baseAlarmID: UUID) async -> String?
}

// MARK: - Shared scheduler facade

enum AlarmScheduler {

    // Visible to other files
    static var forceUNFallback: Bool {
        UserDefaults.standard.bool(forKey: "debug.forceUNFallback")
    }

    // Minimal protocol used across the app
    @MainActor
    protocol AlarmScheduling {
        func requestAuthorizationIfNeeded() async throws
        func schedule(stack: Stack, calendar: Calendar) async throws -> [String]
        func cancelAll(for stack: Stack) async
        func rescheduleAll(stacks: [Stack], calendar: Calendar) async
    }

    // Concrete proxy so callers don’t care which backend is active
    @MainActor
    final class SchedulerProxy: AlarmScheduling {
        #if canImport(AlarmKit)
        let ak = AlarmKitScheduler.shared
        #endif
        let un = UserNotificationScheduler.shared

        func requestAuthorizationIfNeeded() async throws {
            #if canImport(AlarmKit)
            if !AlarmScheduler.forceUNFallback { try await ak.requestAuthorizationIfNeeded(); return }
            #endif
            try await un.requestAuthorizationIfNeeded()
        }

        func schedule(stack: Stack, calendar: Calendar) async throws -> [String] {
            #if canImport(AlarmKit)
            if !AlarmScheduler.forceUNFallback { return try await ak.schedule(stack: stack, calendar: calendar) }
            #endif
            return try await un.schedule(stack: stack, calendar: calendar)
        }

        func cancelAll(for stack: Stack) async {
            #if canImport(AlarmKit)
            if !AlarmScheduler.forceUNFallback { await ak.cancelAll(for: stack); return }
            #endif
            await un.cancelAll(for: stack)
        }

        func rescheduleAll(stacks: [Stack], calendar: Calendar) async {
            #if canImport(AlarmKit)
            if !AlarmScheduler.forceUNFallback {
                await ak.rescheduleAll(stacks: stacks, calendar: calendar)
                return
            }
            #endif
            // Fallback behaviour: reschedule only armed stacks via UN path.
            for s in stacks where s.isArmed {
                _ = try? await un.schedule(stack: s, calendar: calendar)
            }
        }
    }

    static let shared = SchedulerProxy()
}

// MARK: - Optional AlarmSnoozing delegation from the proxy

@MainActor
extension AlarmScheduler.SchedulerProxy: AlarmSnoozing {
    @discardableResult
    func snoozeFromIntent(baseAlarmID: UUID) async -> String? {
        #if canImport(AlarmKit)
        if !AlarmScheduler.forceUNFallback {
            return await ak.snoozeFromIntent(baseAlarmID: baseAlarmID)
        }
        #endif
        // UN fallback has no chain-shift; do nothing.
        return nil
    }
}
