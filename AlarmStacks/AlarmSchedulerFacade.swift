//
//  AlarmSchedulerFacade.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation

/// Unified access point so call sites can use `AlarmScheduler.shared` regardless of backend.
enum AlarmScheduler {
    static var shared: AlarmScheduling = {
        #if canImport(AlarmKit)
        return AlarmKitScheduler.shared
        #else
        return UserNotificationScheduler.shared
        #endif
    }()
}
