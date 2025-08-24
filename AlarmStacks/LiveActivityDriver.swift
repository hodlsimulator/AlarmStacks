//
//  LiveActivityDriver.swift
//  AlarmKit
//
//  Created by . . on 8/16/25.
//

import Foundation

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// Protocol abstraction so this driver can be unit-tested without ActivityKit.
public protocol LiveActivityStarter {
    /// Start the Live Activity for the provided effective target.
    /// Implementations should return `true` when the OS accepted the request.
    func startLiveActivity(effTarget: Date) async throws -> Bool
}

/// Coordinates planning and execution of Live Activity prearm attempts.
/// This version does **not** self-gate on “late windows” or attempt exhaustion.
public final class LiveActivityDriver {

    private let starter: LiveActivityStarter
    private let queue = DispatchQueue(label: "live-activity-driver")

    public init(starter: LiveActivityStarter) {
        self.starter = starter
    }

    /// Schedule prearm attempts for a given target.
    /// Call this when you (re)schedule a step; it will enqueue safe attempt times.
    /// - Parameters:
    ///   - effTarget: the effective target fire date
    ///   - stackID: optional identifier for logging parity with existing AK logs
    public func schedule(for effTarget: Date, stackID: UUID? = nil) {
        let now = Date()
        let attempts = LiveActivityPlanner.plannedAttempts(for: effTarget, now: now)

        if let stackID {
            log("[LA] prearm plan stack=\(stackID.uuidString) effTarget=\(fmt(effTarget)) attempts=\(attempts.map { leadString(effTarget, $0) }.joined(separator: ", "))s")
        } else {
            log("[LA] prearm plan effTarget=\(fmt(effTarget)) attempts=\(attempts.map { leadString(effTarget, $0) }.joined(separator: ", "))s")
        }

        for when in attempts {
            scheduleOne(effTarget: effTarget, when: when)
        }
    }

    /// Schedules a single attempt at a concrete time.
    private func scheduleOne(effTarget: Date, when: Date) {
        let delay = max(0, when.timeIntervalSinceNow)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            Task {
                await self.performAttempt(effTarget: effTarget)
            }
        }
    }

    /// Performs an attempt — no driver-level skip logic; let the app-layer decide.
    private func performAttempt(effTarget: Date) async {
        let now = Date()
        let lead = Int(effTarget.timeIntervalSince(now))

        do {
            let accepted = try await starter.startLiveActivity(effTarget: effTarget)
            if accepted {
                log("[LA] attempt OK lead=\(lead)s effTarget=\(fmt(effTarget))")
            } else {
                log("[LA] attempt DECLINED lead=\(lead)s effTarget=\(fmt(effTarget))")
            }
        } catch {
            log("[LA] attempt FAILED lead=\(lead)s effTarget=\(fmt(effTarget)) error=\(error)")
        }
    }

    // MARK: - Helpers

    private func leadString(_ target: Date, _ when: Date) -> String {
        let lead = Int(target.timeIntervalSince(when))
        return "\(lead)"
    }

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS xxxx"
        return f.string(from: d)
    }

    private func log(_ s: String) {
        // Keep format similar to existing logs.
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS xxxx"
        let ts = df.string(from: Date())
        print("[\(ts)] \(s)")
    }
}
