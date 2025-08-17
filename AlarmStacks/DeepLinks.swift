//
//  DeepLinks.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AlarmKit)
import AlarmKit
#endif

enum DeepLinks {
    static func handle(_ url: URL) {
        guard url.scheme == "alarmstacks" else { return }

        // alarmstacks://action/{stop|snooze}?alarmID=...
        if url.host == "action" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let idString = comps?.queryItems?.first(where: { $0.name == "alarmID" })?.value
            let action = url.pathComponents.dropFirst().first // "stop" or "snooze"

            #if canImport(AlarmKit)
            if let action {
                if let idString, let uuid = UUID(uuidString: idString) {
                    if action == "stop" { try? AlarmManager.shared.stop(id: uuid) }
                    if action == "snooze" { try? AlarmManager.shared.countdown(id: uuid) }
                    return
                }
                // Fallback: act on the alerting alarm (if any)
                let controller = AlarmController.shared
                if let ringing = controller.lastSnapshot.first(where: { $0.state == .alerting }) {
                    if action == "stop" { controller.stop(ringing.id) }
                    if action == "snooze" { controller.snooze(ringing.id) }
                }
            }
            #endif
        }
    }
}
