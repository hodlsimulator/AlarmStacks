//
//  Versioning.swift
//  AlarmStacks
//
//  Created by . . on 8/21/25.
//

import Foundation

public let versionString: String = {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    return "\(v) (\(b))"
}()
