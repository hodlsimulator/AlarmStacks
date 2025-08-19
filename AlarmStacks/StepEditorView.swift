//
//  StepEditorView.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct StepEditorView: View {

    @Bindable var step: Step

    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {
        Form {
            basicsSection
            kindSection

            switch step.kind {
            case .fixedTime:
                fixedTimeSection
                weekdaysSection
            case .timer: // existing timers remain editable (legacy)
                timerSection
                cadenceSection
            case .relativeToPrev:
                afterPreviousSection
            }

            behaviourSection
        }
        .navigationTitle("Edit Step")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task { await saveAndReschedule() }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTapAnywhere()      // ← tap anywhere to dismiss keyboard (doesn’t block taps)
        .themedSurface()                     // ← pushed via navigation, not a sheet
    }

    // MARK: - Sections

    private var basicsSection: some View {
        Section("Basics") {
            TextField("Title", text: $step.title)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)

            Toggle("Enabled", isOn: $step.isEnabled)
        }
    }

    private var kindSection: some View {
        Section("Step type") {
            // No "Timer" option for new or non-timer steps.
            // If the step is a legacy Timer, show a read-only label instead of a picker.
            if step.kind == .timer {
                LabeledContent("Type") {
                    Text("Timer (legacy)")
                        .foregroundStyle(.secondary)
                        .singleLineTightTail()
                }
            } else {
                Picker("Type", selection: $step.kind) {
                    Text("Fixed time").tag(StepKind.fixedTime)
                    Text("After previous").tag(StepKind.relativeToPrev)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var fixedTimeSection: some View {
        Section("Fixed time") {
            DatePicker(
                "Time",
                selection: Binding<Date>(
                    get: { timeFromHourMinute() },
                    set: { setHourMinute(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        }
    }

    private var weekdaysSection: some View {
        Section {
            WeekdayChips(selected: Binding(
                get: { Set(step.weekdays ?? []) },
                set: { new in
                    let sorted = Array(new).sorted()
                    step.weekdays = sorted.isEmpty ? [] : sorted
                    step.weekday = nil
                }
            ))
        } header: {
            Text("Repeat on").singleLineTightTail()
        } footer: {
            Text("Leave all off to allow any day.")
                .singleLineTightTail()
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var timerSection: some View {
        Section("Timer") {
            DurationEditor(
                label: "Duration",
                seconds: Binding(
                    get: { max(1, step.durationSeconds ?? 60) },
                    set: { step.durationSeconds = max(1, $0) }
                )
            )
        }
    }

    private var cadenceSection: some View {
        Section("Every N days (optional)") {
            Toggle(isOn: Binding<Bool>(
                get: { (step.everyNDays ?? 0) > 1 },
                set: { on in
                    step.everyNDays = on ? max(2, step.everyNDays ?? 2) : nil
                }
            )) {
                Text("Gate timer to a day cadence").singleLineTightTail()
            }

            if (step.everyNDays ?? 0) > 1 {
                Stepper(value: Binding(
                    get: { max(2, step.everyNDays ?? 2) },
                    set: { step.everyNDays = max(2, $0) }
                ), in: 2...365) {
                    Text("Every \(step.everyNDays ?? 2) days").singleLineTightTail()
                }
            }
        }
    }

    private var afterPreviousSection: some View {
        Section("After previous") {
            Picker("Direction", selection: Binding<Direction>(
                get: { (step.offsetSeconds ?? 60) >= 0 ? .after : .before },
                set: { dir in
                    let mag = abs(step.offsetSeconds ?? 60)
                    step.offsetSeconds = dir == .after ? mag : -mag
                }
            )) {
                Text("After").tag(Direction.after)
                Text("Before").tag(Direction.before)
            }
            .pickerStyle(.segmented)

            DurationEditor(
                label: "Delay",
                seconds: Binding(
                    get: { abs(step.offsetSeconds ?? 60) },
                    set: { newValue in
                        let sign = (step.offsetSeconds ?? 60) >= 0 ? 1 : -1
                        step.offsetSeconds = sign * max(0, newValue)
                    }
                )
            )

            Text(relativePhrase(seconds: step.offsetSeconds ?? 60))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .accessibilityLabel("Human-readable delay")
                .singleLineTightTail()
        }
    }

    private var behaviourSection: some View {
        Section("Behaviour") {
            Toggle("Allow snooze", isOn: $step.allowSnooze)

            Stepper(value: $step.snoozeMinutes, in: 1...30) {
                if step.snoozeMinutes == 1 {
                    Text("Snooze for 1 minute").singleLineTightTail()
                } else {
                    Text("Snooze for \(step.snoozeMinutes) minutes").singleLineTightTail()
                }
            }
            .disabled(!step.allowSnooze)
        }
    }

    // MARK: - Save & reschedule

    private func saveAndReschedule() async {
        try? modelContext.save()

        if let stack = step.stack, stack.isArmed {
            await AlarmScheduler.shared.cancelAll(for: stack)
            _ = try? await AlarmScheduler.shared.schedule(stack: stack, calendar: calendar)
        }

        dismiss()
    }

    // MARK: - Helpers (time <-> hour/minute)

    private func timeFromHourMinute() -> Date {
        let h = step.hour ?? 7
        let m = step.minute ?? 0
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    private func setHourMinute(from date: Date) {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        step.hour = comps.hour
        step.minute = comps.minute
    }

    // MARK: - Friendly phrasing

    private func relativePhrase(seconds: Int) -> String {
        let value = seconds
        let s = abs(value)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60

        let dur: String = {
            if h > 0 { return "\(h)h \(m)m" }
            if m > 0 && sec > 0 { return "\(m)m \(sec)s" }
            if m > 0 { return "\(m)m" }
            return "\(sec)s"
        }()

        return value >= 0 ? "\(dur) after previous" : "\(dur) before previous"
    }
}

// MARK: - Direction

private enum Direction: Hashable {
    case after
    case before
}

// MARK: - DurationEditor / WeekdayChips

private struct DurationEditor: View {
    let label: String
    @Binding var seconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(label) {
                Text(formatted(seconds: seconds))
                    .monospacedDigit()
                    .singleLineTightTail()
            }

            HStack {
                Stepper(value: Binding(
                    get: { seconds / 60 },
                    set: { mins in
                        let secs = seconds % 60
                        seconds = max(0, mins) * 60 + secs
                    }
                ), in: 0...720) {
                    Text("Minutes: \(seconds / 60)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .singleLineTightTail()
                }

                Stepper(value: Binding(
                    get: { seconds % 60 },
                    set: { s in
                        let mins = seconds / 60
                        seconds = mins * 60 + max(0, min(59, s))
                    }
                ), in: 0...59) {
                    Text("Seconds: \(seconds % 60)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .singleLineTightTail()
                }
            }
            .labelStyle(.titleOnly)
        }
    }

    private func formatted(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }
}

private struct WeekdayChips: View {
    @Binding var selected: Set<Int> // 1...7, Sunday = 1

    private let days: [(num: Int, short: String)] = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"),
        (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.num) { d in
                        Button {
                            toggle(d.num)
                        } label: {
                            Text(d.short)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .allowsTightening(true)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(selected.contains(d.num) ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                                .foregroundStyle(selected.contains(d.num) ? .primary : .secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 12) {
                Button("Clear") { selected.removeAll() }
                Button("Weekdays") { selected = [2,3,4,5,6] }
                Button("Weekends") { selected = [1,7] }
            }
            .font(.footnote)
        }
        .accessibilityElement(children: .contain)
    }

    private func toggle(_ n: Int) {
        if selected.contains(n) { selected.remove(n) } else { selected.insert(n) }
    }
}
