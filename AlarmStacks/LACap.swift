//
//  LACap.swift
//  AlarmStacks
//
//  Created by . . on 8/24/25.
//

import Foundation

@MainActor
enum LACap {
    private static var cooldownUntil: Date = .distantPast

    static var inCooldown: Bool { Date() < cooldownUntil }

    static func enterCooldown(seconds: TimeInterval, reason: String) {
        cooldownUntil = Date().addingTimeInterval(seconds)
        DiagLog.log("[ACT] cap.cooldown reason=\(reason) until=\(DiagLog.f(cooldownUntil))")
    }

    static func clear() {
        cooldownUntil = .distantPast
        DiagLog.log("[ACT] cap.cooldown cleared")
    }
}
