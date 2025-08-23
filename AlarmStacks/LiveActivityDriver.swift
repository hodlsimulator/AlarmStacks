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

/// Lightweight rate limiter to avoid spamming start attempts when we're already too late.
public final class AttemptGate {
    private var attempts: [String: Int] = [:]
    private let maxAttemptsPerTarget: Int

    public init(maxAttemptsPerTarget: Int = 3) {
        self.maxAttemptsPerTarget = maxAttemptsPerTarget
    }

    public func shouldAttempt(key: String) -> Bool {
        let count = attempts[key, default: 0]
        if count >= maxAttemptsPerTarget { return false }
        attempts[key] = count + 1
        return true
    }
}

/// Coordinates planning and execution of Live Activity prearm attempts.
public final class LiveActivityDriver {

    private let starter: LiveActivityStarter
    private let gate = AttemptGate(maxAttemptsPerTarget: 3)
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

    /// Performs a guarded start attempt. If we're inside the late-start window, we skip instead of
    /// hammering ActivityKit (which previously yielded `targetMaximumExceeded` repeatedly).
    private func performAttempt(effTarget: Date) async {
        let now = Date()
        let lead = effTarget.timeIntervalSince(now)

        // Late-start guard.
        if lead < LiveActivityPlanner.hardMinimumLeadSeconds {
            log("[ACT] start SKIP reason=late-window lead=\(Int(lead))s effTarget=\(fmt(effTarget))")
            return
        }

        // Backoff/limit repeat attempts per target.
        let key = Self.key(for: effTarget)
        guard gate.shouldAttempt(key: key) else {
            log("[ACT] start SKIP reason=attempts-exhausted effTarget=\(fmt(effTarget))")
            return
        }

        do {
            let accepted = try await starter.startLiveActivity(effTarget: effTarget)
            if accepted {
                log("[ACT] start OK lead=\(Int(lead))s effTarget=\(fmt(effTarget))")
            } else {
                // Starter declined (e.g., visibility conditions). We do not reschedule here;
                // any additional planned attempts will still run if they were pre-enqueued.
                log("[ACT] start DECLINED lead=\(Int(lead))s effTarget=\(fmt(effTarget))")
            }
        } catch {
            // Classify common "too late" errors so we don't thrash.
            if Self.isTargetMaximumExceeded(error) {
                log("[ACT] start FAILED error=targetMaximumExceeded lead=\(Int(lead))s effTarget=\(fmt(effTarget)) (will not retry immediately)")
            } else {
                log("[ACT] start FAILED error=\(error) lead=\(Int(lead))s effTarget=\(fmt(effTarget))")
            }
        }
    }

    // MARK: - Helpers

    private static func key(for effTarget: Date) -> String {
        String(Int(effTarget.timeIntervalSince1970))
    }

    /// Best-effort classification without leaking ActivityKit types out of the starter.
    private static func isTargetMaximumExceeded(_ error: Error) -> Bool {
        let s = String(describing: error).lowercased()
        return s.contains("targetmaximumexceeded") || s.contains("target maximum exceeded") || s.contains("too late")
    }

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
