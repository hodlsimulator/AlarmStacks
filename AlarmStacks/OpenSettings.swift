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
    #if canImport(UIKit)
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    #endif
}
