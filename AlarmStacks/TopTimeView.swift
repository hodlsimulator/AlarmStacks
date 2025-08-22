//
//  TopTimeView.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import SwiftUI

struct TopTimeView: View {
    let nextDate: Date?
    let canArm: Bool
    @Environment(\.calendar) private var calendar

    var body: some View {
        if let next = nextDate {
            VStack(spacing: 0) { // tighter to reduce depth
                Text(timeString(next))
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text("\(dayWord(next)) · \(relativeString(next))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .singleLineTightTail()
                    .padding(.top, 1)
            }
        } else {
            if canArm {
                Text("No upcoming time")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .singleLineTightTail()
            } else {
                Label("Needs a start time", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
                    .singleLineTightTail()
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("HH:mm")
        return f.string(from: date)
    }
    private func dayWord(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: date)
    }
    private func relativeString(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
