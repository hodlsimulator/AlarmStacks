//
//  AlarmKitScheduler+Test.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//

#if canImport(AlarmKit)
import Foundation
import SwiftUI
import AlarmKit
import ActivityKit
import AppIntents

@MainActor
extension AlarmKitScheduler {
    @discardableResult
    func scheduleTestRing(in seconds: Int = 5) async -> String? {
        do {
            try await requestAuthorizationIfNeeded()

            let id = UUID()
            let delay = max(1, seconds)
            let target = Date().addingTimeInterval(TimeInterval(delay))

            let title: LocalizedStringResource = LocalizedStringResource("Test Alarm")
            let stopI = StopAlarmIntent(alarmID: id.uuidString)

            // Build a minimal alert + attributes here (no private helpers)
            let stop = AlarmButton(
                text: LocalizedStringResource("Stop"),
                textColor: .white,
                systemImageName: "stop.fill"
            )
            let alert = AlarmPresentation.Alert(
                title: title,
                stopButton: stop,
                secondaryButton: nil,
                secondaryButtonBehavior: nil
            )
            let attrs = AlarmAttributes<EmptyMetadata>(
                presentation: AlarmPresentation(alert: alert),
                tintColor: ThemeTintResolver.currentAccent()
            )

            let cfg: AlarmManager.AlarmConfiguration<EmptyMetadata> = .timer(
                duration: TimeInterval(delay),
                attributes: attrs,
                stopIntent: stopI,
                secondaryIntent: nil,
                sound: .default
            )
            
            _ = try await AlarmManager.shared.schedule(id: id, configuration: cfg)

            // Simple diag
            UserDefaults.standard.set(target.timeIntervalSince1970, forKey: "ak.effTarget.\(id.uuidString)")
            DiagLog.log("AK test schedule id=\(id.uuidString) in \(delay)s; target=\(DiagLog.f(target))")

            return id.uuidString
        } catch {
            DiagLog.log("AK test schedule FAILED error=\(error)")
            return nil
        }
    }
}
#endif
