//
//  ModelAliases.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation

typealias AlarmStack = Stack
typealias AlarmStep  = Step

#if canImport(AlarmKit)
typealias AlarmScheduler = AppAlarmKitScheduler
#else
typealias AlarmScheduler = LocalNotificationScheduler
#endif
