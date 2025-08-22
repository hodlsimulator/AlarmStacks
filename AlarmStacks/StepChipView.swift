//
//  StepChipView.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import SwiftUI

/// Compact chip used in stack rows to display individual steps.
/// Visuals use `glassChip(...)` (see CardStyle.swift).
struct StepChip: View {
    let step: Step

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: step)).imageScale(.small)
            Text(label(for: step))
                .font(.caption)
                .layoutPriority(1)
                .singleLineTightTail(minScale: 0.85)
        }
        .glassChip(state: chipState(for: step))
        .accessibilityLabel(accessibility(for: step))
    }

    // MARK: - Visual state

    private func chipState(for step: Step) -> GlassChipModifier.State {
        if !step.isEnabled { return .disabled }
        if step.kind == .timer { return .legacy } // legacy timer visual cue
        return .normal
    }

    // MARK: - Content

    private func icon(for step: Step) -> String {
        switch step.kind {
        case .fixedTime:     return "alarm"
        case .timer:         return "exclamationmark.circle"   // legacy cue
        case .relativeToPrev:return "plus.circle"
        }
    }

    private func label(for step: Step) -> String {
        switch step.kind {
        case .fixedTime:
            var time = "Time"
            if let h = step.hour, let m = step.minute {
                time = String(format: "%02d:%02d", h, m)
            }
            let days = daysText(for: step)
            return days.isEmpty ? "\(time)  \(step.title)" : "\(time) • \(days)  \(step.title)"

        case .timer:
            if let s = step.durationSeconds { return "Legacy · \(format(seconds: s))  \(step.title)" }
            return "Legacy  \(step.title)"

        case .relativeToPrev:
            if let s = step.offsetSeconds {
                let sign = s >= 0 ? "+" : "−"
                return "\(sign)\(format(seconds: abs(s)))  \(step.title)"
            }
            return step.title
        }
    }

    private func accessibility(for step: Step) -> String {
        let prefix: String = {
            if !step.isEnabled { return "Disabled" }
            if step.kind == .timer { return "Legacy timer" }
            return "Enabled"
        }()
        return "\(prefix), \(label(for: step))"
    }

    // MARK: - Helpers

    private func format(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    private func daysText(for step: Step) -> String {
        let map = [2:"Mon",3:"Tue",4:"Wed",5:"Thu",6:"Fri",7:"Sat",1:"Sun"]
        let chosen: [Int]
        if let arr = step.weekdays, !arr.isEmpty { chosen = arr }
        else if let one = step.weekday { chosen = [one] }
        else { return "" }

        let set = Set(chosen)
        if set.count == 7 { return "Every day" }
        if set == Set([2,3,4,5,6]) { return "Weekdays" }
        if set == Set([1,7]) { return "Weekend" }
        let order = [2,3,4,5,6,7,1]
        return order.filter { set.contains($0) }.compactMap { map[$0] }.joined(separator: " ")
    }
}
