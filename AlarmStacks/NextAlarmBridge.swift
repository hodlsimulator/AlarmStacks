//
//  NextAlarmBridge.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation

enum SharedIDs {
    // CHANGE THIS to your App Group ID (add capability in both targets)
    static let appGroup = "group.com.hodlsimulator.alarmstacks"
    static let nextAlarmKey = "nextAlarm.v1"
}

struct NextAlarmInfo: Codable, Equatable {
    var stackName: String
    var stepTitle: String
    var fireDate: Date
}

enum NextAlarmBridge {
    private static var suite: UserDefaults? { UserDefaults(suiteName: SharedIDs.appGroup) }

    static func write(_ info: NextAlarmInfo) {
        if let data = try? JSONEncoder().encode(info) {
            suite?.set(data, forKey: SharedIDs.nextAlarmKey)
        }
    }

    static func read() -> NextAlarmInfo? {
        guard let data = suite?.data(forKey: SharedIDs.nextAlarmKey) else { return nil }
        return try? JSONDecoder().decode(NextAlarmInfo.self, from: data)
    }

    static func clear() {
        suite?.removeObject(forKey: SharedIDs.nextAlarmKey)
    }
}
