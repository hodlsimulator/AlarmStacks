//
//  NextAlarmBridge.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum SharedIDs {
    // Make sure this EXACTLY matches the App Group in BOTH targets' entitlements.
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

    static func write(_ info: NextAlarmInfo, reloadWidget: Bool = true) {
        if let data = try? JSONEncoder().encode(info) {
            suite?.set(data, forKey: SharedIDs.nextAlarmKey)
        }
        #if canImport(WidgetKit)
        if reloadWidget, #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "NextAlarmWidget")
        }
        #endif
    }

    static func read() -> NextAlarmInfo? {
        guard let data = suite?.data(forKey: SharedIDs.nextAlarmKey) else { return nil }
        return try? JSONDecoder().decode(NextAlarmInfo.self, from: data)
    }

    static func clear(reloadWidget: Bool = true) {
        suite?.removeObject(forKey: SharedIDs.nextAlarmKey)
        #if canImport(WidgetKit)
        if reloadWidget, #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "NextAlarmWidget")
        }
        #endif
    }
}
