//
//  AlarmSchedulerFacade.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation

enum AlarmScheduler {
    private static var forceUNFallback: Bool {
        UserDefaults.standard.bool(forKey: "debug.forceUNFallback")
    }

    static var shared: AlarmScheduling {
        #if canImport(AlarmKit)
        return forceUNFallback ? UserNotificationScheduler.shared : AlarmKitScheduler.shared
        #else
        return UserNotificationScheduler.shared
        #endif
    }
}
