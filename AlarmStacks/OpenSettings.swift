//
//  OpenSettings.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

func openAppSettings() {
    // Mark so ForegroundRearmCoordinator knows to re-arm when we come back.
    SettingsRearmGate.mark()
    #if canImport(UIKit)
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    #endif
}
