//
//  ThemePickerView.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI

// MARK: - Theme model

private struct ThemeOption: Identifiable, Hashable {
    let id: String
    let name: String
    let tint: Color
    let requiresPlus: Bool
}

private let themeOptions: [ThemeOption] = [
    // Free
    ThemeOption(id: "Default",  name: "Default",  tint: Color(red: 0.04, green: 0.52, blue: 1.00), requiresPlus: false), // iOS blue
    ThemeOption(id: "Forest",   name: "Forest",   tint: Color(red: 0.16, green: 0.62, blue: 0.39), requiresPlus: false),
    ThemeOption(id: "Coral",    name: "Coral",    tint: Color(red: 0.98, green: 0.45, blue: 0.35), requiresPlus: false),

    // Plus
    ThemeOption(id: "Indigo",   name: "Indigo",   tint: Color(red: 0.35, green: 0.37, blue: 0.80), requiresPlus: true),
    ThemeOption(id: "Grape",    name: "Grape",    tint: Color(red: 0.56, green: 0.27, blue: 0.68), requiresPlus: true),
    ThemeOption(id: "Mint",     name: "Mint",     tint: Color(red: 0.22, green: 0.77, blue: 0.58), requiresPlus: true),
    ThemeOption(id: "Flamingo", name: "Flamingo", tint: Color(red: 1.00, green: 0.35, blue: 0.62), requiresPlus: true),
    ThemeOption(id: "Slate",    name: "Slate",    tint: Color(red: 0.36, green: 0.42, blue: 0.49), requiresPlus: true),
    ThemeOption(id: "Midnight", name: "Midnight", tint: Color(red: 0.10, green: 0.14, blue: 0.28), requiresPlus: true)
]

// MARK: - Theme picker

struct ThemePickerView: View {
    @AppStorage("themeName") private var themeName: String = "Default"
    @StateObject private var store = Store.shared
    @State private var showingPaywall = false

    var body: some View {
        Section("Theme colour") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 12) {
                ForEach(themeOptions) { opt in
                    Button {
                        if opt.requiresPlus && !store.isPlus {
                            showingPaywall = true
                        } else {
                            themeName = opt.id
                        }
                    } label: {
                        ThemeChip(option: opt, selected: themeName == opt.id, locked: opt.requiresPlus && !store.isPlus)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            Text(store.isPlus
                 ? "Choose a colour you like. Changes apply across the app."
                 : "Unlock more colours with AlarmStacks Plus.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .task { await store.load() }
    }
}

private struct ThemeChip: View {
    let option: ThemeOption
    let selected: Bool
    let locked: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(option.tint.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? option.tint : Color.secondary.opacity(0.35),
                                          lineWidth: selected ? 2 : 1)
                    )
                    .frame(height: 58)

                Image(systemName: locked ? "lock.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                    .imageScale(.large)
                    .foregroundColor(locked ? Color.secondary : (selected ? option.tint : Color.secondary))
            }
            Text(option.name)
                .font(.footnote)
                .lineLimit(1)
        }
        .frame(minWidth: 88)
    }
}

// MARK: - App-wide tint applier

struct AppTint: ViewModifier {
    @AppStorage("themeName") private var themeName: String = "Default"

    func body(content: Content) -> some View {
        content.tint(tintColor(for: themeName))
    }

    private func tintColor(for name: String) -> Color {
        themeOptions.first(where: { $0.id == name })?.tint ?? themeOptions[0].tint
    }
}

extension View {
    func appTint() -> some View { modifier(AppTint()) }
}
