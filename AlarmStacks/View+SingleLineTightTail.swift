//
//  View+SingleLineTightTail.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI

public extension View {
    /// One-line, prefers tightening, scales down slightly, then truncates at tail.
    func singleLineTightTail(minScale: CGFloat = 0.88) -> some View {
        self
            .lineLimit(1)
            .allowsTightening(true)
            .minimumScaleFactor(minScale)
            .truncationMode(.tail)
    }
}
