//
//  AlarmControlIntents.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import AppIntents
#if canImport(AlarmKit)
import AlarmKit
#endif

struct StopAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Alarm"
    static var description = IntentDescription("Stop the currently alerting alarm.")
    static var openAppWhenRun = true

    @Parameter(title: "Alarm ID") var alarmID: String
    init() { self.alarmID = "" }
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        #if canImport(AlarmKit)
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.stop(id: id) }
        #endif
        return .result()
    }
}

struct SnoozeAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze Alarm"
    static var description = IntentDescription("Snooze the current alarm.")
    static var openAppWhenRun = false

    @Parameter(title: "Alarm ID") var alarmID: String
    init() { self.alarmID = "" }
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        #if canImport(AlarmKit)
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.countdown(id: id) }
        #endif
        return .result()
    }
}
