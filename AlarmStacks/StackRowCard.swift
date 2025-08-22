//
//  StackRowCard.swift
//  AlarmStacks
//
//  Created by . . on 8/23/25.
//

import SwiftUI

struct StackRowCard: View {
    @Bindable var stack: Stack
    var onToggleArm: () -> Void
    var onDuplicate: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    // Step-chip actions
    var onEditStep: (Step) -> Void
    var onDuplicateStep: (Step) -> Void
    var onToggleStepEnabled: (Step) -> Void

    var canArm: (Stack) -> Bool

    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var scheme

    // Keep corner icons visually inside the 18pt corner radius.
    private let cornerInset: CGFloat = 14

    var body: some View {
        StackCardShell(accent: stackAccent(for: stack)) {
            VStack(alignment: .leading, spacing: 6) {

                // Centred time – decorative
                HStack {
                    Spacer(minLength: 0)
                    TopTimeView(nextDate: nextStart(for: stack), canArm: canArm(stack))
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
                .allowsHitTesting(false)

                // Title row
                NavigationLink(value: stack) {
                    HStack(spacing: 8) {
                        Text(stack.name)
                            .font(.headline)
                            .layoutPriority(1)
                            .singleLineTightTail()

                        if stack.isArmed { ArmedLED() }

                        Spacer(minLength: 0)

                        Text("\(stack.sortedSteps.count) step\(stack.sortedSteps.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .singleLineTightTail()
                    }
                }
                .buttonStyle(.plain)

                // Step chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stack.sortedSteps) { step in
                            StepChip(step: step)
                                .contentShape(Capsule())
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    lightHaptic()
                                    onEditStep(step)
                                }
                                .onTapGesture { lightHaptic() }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
                .scrollClipDisabled()
                .frame(minHeight: 32)
            }
        }
        // Corner buttons as overlays (no glass background → no circles)
        .overlay(alignment: .topLeading) {
            Button {
                lightHaptic()
                onDuplicate()
            } label: {
                Image(systemName: "square.on.square")
                    .imageScale(.medium)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel("Duplicate stack")
            }
            .buttonStyle(.plain)
            .padding(.leading, cornerInset)
            .padding(.top, cornerInset)
            .contentShape(Rectangle())          // large hit target
            .padding(6)                         // extra invisible hit slop
        }
        .overlay(alignment: .topTrailing) {
            Button {
                lightHaptic()
                onToggleArm()
            } label: {
                Image(systemName: stack.isArmed ? "power.circle.fill" : "power.circle")
                    .imageScale(.medium)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(stack.isArmed ? "Disarm" : "Arm")
            }
            .buttonStyle(.plain)
            .padding(.trailing, cornerInset)
            .padding(.top, cornerInset)
            .contentShape(Rectangle())          // large hit target
            .padding(6)                         // extra invisible hit slop
            .disabled(!canArm(stack))
            .opacity(canArm(stack) ? 1.0 : 0.45)
        }
        .contextMenu {
            Group {
                if stack.isArmed {
                    Button(role: .none, action: onToggleArm) { Label("Disarm", systemImage: "bell.slash.fill") }
                } else {
                    Button(role: .none, action: onToggleArm) { Label("Arm", systemImage: "bell.fill") }
                }
            }
            Divider()
            Button(action: onDuplicate) { Label("Duplicate", systemImage: "square.on.square") }
            Button(action: onRename)    { Label("Rename", systemImage: "pencil") }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    private func nextStart(for stack: Stack) -> Date? {
        let base = Date()
        for step in stack.sortedSteps where step.isEnabled {
            switch step.kind {
            case .fixedTime, .timer, .relativeToPrev:
                if let d = try? step.nextFireDate(basedOn: base, calendar: calendar) { return d }
                else { return nil }
            }
        }
        return nil
    }
}

// Haptics (tiny, precise)
private func lightHaptic() {
    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif
}

private func stackAccent(for stack: Stack) -> Color {
    let palette: [Color] = [
        Color(red: 0.70, green: 0.83, blue: 1.00),
        Color(red: 0.74, green: 0.90, blue: 0.82),
        Color(red: 1.00, green: 0.86, blue: 0.67),
        Color(red: 0.87, green: 0.79, blue: 0.99),
        Color(red: 1.00, green: 0.78, blue: 0.88),
        Color(red: 0.78, green: 0.92, blue: 0.92),
        Color(red: 0.81, green: 0.86, blue: 1.00),
        Color(red: 1.00, green: 0.92, blue: 0.68)
    ]
    let idx = abs(stack.id.uuidString.hashValue) % palette.count
    return palette[idx]
}
