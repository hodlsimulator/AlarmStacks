//
//  Item.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import SwiftData
import Combine

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
