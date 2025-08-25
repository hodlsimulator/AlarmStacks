//
//  LiveActivityManager+Start.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//
//  NOTE: The LA start/retry/prearm logic has been consolidated into
//  `LiveActivityReliability.swift` (LAEnsure). This file is kept as a harmless
//  shim so project references remain intact.
//

import Foundation

@MainActor
extension LAEnsure {
    // Intentionally empty. All logic now lives in LiveActivityReliability.swift.
}
