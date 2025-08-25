//
//  TimerEngine.swift
//  AlarmStacks
//
//  Created by . . on 8/25/25.
//

import Foundation
import SwiftUI
import AlarmKit

@MainActor
final class TimerEngine {
    static let shared = TimerEngine()
    private let manager = AlarmManager.shared

    private(set) var activeID: UUID?

    enum EngineError: Error { case notAuthorised }

    // Ask for permission if needed.
    func ensureAuthorised() async throws {
        switch manager.authorizationState {
        case .authorized:
            return
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            guard state == .authorized else { throw EngineError.notAuthorised }
        default:
            throw EngineError.notAuthorised
        }
    }

    /// Start a true AlarmKit countdown (works for very short timers like 10s).
    @discardableResult
    func start(seconds: Int, title: String = "Timer", tint: Color = .orange) async throws -> UUID {
        try await ensureAuthorised()

        // Cancel any existing timer first. (cancel is NOT async)
        if let id = activeID {
            try? manager.cancel(id: id)
            activeID = nil
        }

        // Button & alert (AlarmKit wants LocalizedStringResource).
        let stop = AlarmButton(
            text: LocalizedStringResource("Stop"),
            textColor: .white,
            systemImageName: "stop.fill"
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title), // dynamic string -> LSR
            stopButton: stop
        )

        // Attributes: make generic concrete by providing metadata explicitly.
        let attrs: AlarmAttributes<TimerLAMetadata> = .init(
            presentation: AlarmPresentation(alert: alert),
            metadata: TimerLAMetadata(),
            tintColor: tint
        )

        // Schedule an immediate countdown.
        let id = UUID()
        _ = try await manager.schedule(
            id: id,
            configuration: .timer(
                duration: Double(seconds),
                attributes: attrs
            )
        )

        activeID = id
        return id
    }

    /// Cancel the current countdown.
    func cancelActive() {
        if let id = activeID {
            try? manager.cancel(id: id)
            activeID = nil
        }
    }
}
