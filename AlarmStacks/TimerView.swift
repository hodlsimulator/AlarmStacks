//
//  TimerView.swift
//  AlarmStacks
//
//  Created by . . on 8/25/25.
//

import SwiftUI
import Combine   // <- needed for Timer.publish

struct TimerView: View {
    @Environment(\.colorScheme) private var systemScheme

    @AppStorage("appearanceMode") private var mode: String = AppearanceMode.system.rawValue
    @AppStorage("themeName")      private var themeName: String = "Default"
    private var appearanceID: String { "\(mode)-\(systemScheme == .dark ? "dark" : "light")-\(themeName)" }

    // Wheel pickers
    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var seconds: Int = 10

    // Runtime state
    @State private var isRunning: Bool = false
    @State private var totalSeconds: Int = 10
    @State private var remainingSeconds: Int = 10
    @State private var targetDate: Date? = nil

    // AlarmKit engine (no ObservableObject wrappers needed)
    private let engine = TimerEngine.shared

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private var bigDigitsFont: Font { .system(size: 120, weight: .bold, design: .rounded) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Text(formatted(remainingSeconds))
                            .font(bigDigitsFont)
                            .minimumScaleFactor(0.3)
                            .monospacedDigit()
                            .lineLimit(1)
                            .singleLineTightTail()
                            .accessibilityLabel("Time remaining")

                        HStack(spacing: 8) {
                            if let end = targetDate, isRunning {
                                Label { Text("Ends at \(end, style: .time)") } icon: { Image(systemName: "clock") }
                            } else {
                                Label { Text("Idle") } icon: { Image(systemName: "pause.fill") }
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        ProgressView(value: progress)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            WheelNumberColumn(title: "Hours",   range: 0...23, selection: $hours)
                            Text(":").font(.title2).monospacedDigit()
                            WheelNumberColumn(title: "Minutes", range: 0...59, selection: $minutes)
                            Text(":").font(.title2).monospacedDigit()
                            WheelNumberColumn(title: "Seconds", range: 0...59, selection: $seconds)
                        }
                        .frame(height: 184)
                        .disabled(isRunning)
                    }
                    .padding(.horizontal, 4)

                    HStack(spacing: 12) {
                        if isRunning {
                            Button { pause() } label: { Label("Pause", systemImage: "pause.circle.fill") }
                                .buttonStyle(.borderedProminent)

                            Button(role: .destructive) { reset() } label: { Label("Reset", systemImage: "stop.circle") }
                                .buttonStyle(.bordered)
                        } else {
                            Button { startOrResume() } label: {
                                Label(remainingSeconds == totalSeconds ? "Start" : "Resume",
                                      systemImage: "play.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(totalSeconds == 0)

                            Button(role: .destructive) { reset() } label: { Label("Reset", systemImage: "stop.circle") }
                                .buttonStyle(.bordered)
                                .disabled(totalSeconds == 0 && (hours+minutes+seconds) == 0)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Timer")
            .themedSurface()
            .background(ThemeSurfaceBackground())
            .safeAreaInset(edge: .bottom) { VersionBadge().allowsHitTesting(false) }
        }
        .onAppear { syncFromPickers() }
        .onChange(of: hours)   { _, _ in syncFromPickersIfNotRunning() }
        .onChange(of: minutes) { _, _ in syncFromPickersIfNotRunning() }
        .onChange(of: seconds) { _, _ in syncFromPickersIfNotRunning() }
        .onReceive(ticker) { _ in tick() }
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    private func startOrResume() {
        if remainingSeconds == totalSeconds || remainingSeconds <= 0 {
            syncFromPickers()
            if totalSeconds == 0 { return }
            remainingSeconds = totalSeconds
        }

        let end = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        targetDate = end
        isRunning = true

        Task { @MainActor in
            // True AlarmKit countdown – no UN notifications, no duplicate LAs
            let tint = ThemeMap.payload(for: themeName).accent.color
            _ = try? await engine.start(seconds: remainingSeconds, title: "Timer", tint: tint)
        }
    }

    private func pause() {
        isRunning = false
        targetDate = nil
        Task { @MainActor in await engine.cancelActive() }
    }

    private func reset() {
        isRunning = false
        targetDate = nil
        Task { @MainActor in await engine.cancelActive() }
        syncFromPickers()
    }

    @discardableResult
    private func tick() -> Bool {
        guard isRunning, let target = targetDate else { return false }
        let newRemaining = max(0, Int(target.timeIntervalSinceNow.rounded()))
        if newRemaining != remainingSeconds { remainingSeconds = newRemaining }
        if newRemaining <= 0 {
            isRunning = false
            targetDate = nil
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            return true
        }
        return false
    }

    private func syncFromPickers() {
        let total = hours * 3600 + minutes * 60 + seconds
        totalSeconds = max(0, total)
        remainingSeconds = totalSeconds
    }

    private func syncFromPickersIfNotRunning() {
        if !isRunning { syncFromPickers() }
    }

    private func formatted(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// Wheel column unchanged
private struct WheelNumberColumn: View {
    let title: String
    let range: ClosedRange<Int>
    @Binding var selection: Int

    var body: some View {
        VStack(spacing: 4) {
            Picker(title, selection: $selection) {
                ForEach(Array(range), id: \.self) { i in
                    Text(String(format: "%02d", i))
                        .monospacedDigit()
                        .tag(i)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .singleLineTightTail()
        }
        .accessibilityElement(children: .contain)
    }
}
