//
//  AKDebugDump.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//

import Foundation

enum AKDebugDump {
    private static func resolveAppGroupDefaults() -> UserDefaults? {
        let candidateKeys = ["AppGroupIdentifier", "AppGroupSuiteName", "ApplicationGroupIdentifier"]
        for key in candidateKeys {
            if let suite = Bundle.main.object(forInfoDictionaryKey: key) as? String {
                return UserDefaults(suiteName: suite)
            }
        }
        return nil
    }

    static func dumpAKKeys() {
        let std = UserDefaults.standard
        let stdKeys = std.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("ak.") || $0.hasPrefix("alarmkit.ids.") }
            .sorted()

        print("----- [AK] STD KEYS -----")
        for k in stdKeys {
            print("\(k) = \(std.object(forKey: k) ?? "nil")")
        }

        if let appGroup = resolveAppGroupDefaults() {
            let grpKeys = appGroup.dictionaryRepresentation().keys
                .filter { $0.hasPrefix("ak.") || $0.hasPrefix("alarmkit.ids.") }
                .sorted()
            print("----- [AK] GROUP KEYS -----")
            for k in grpKeys {
                print("\(k) = \(appGroup.object(forKey: k) ?? "nil")")
            }
        } else {
            print("----- [AK] GROUP KEYS ----- (no app group configured)")
        }
    }
}
