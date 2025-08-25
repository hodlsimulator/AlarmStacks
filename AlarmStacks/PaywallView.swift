//
//  PaywallView.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import StoreKit
import Combine

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var router: ModalRouter
    @StateObject private var store = Store.shared
    @State private var purchasingID: String?

    // Layout
    private var isAccessibilitySize: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                        .padding(.top, 6)

                    // Products section adapts: horizontal cards normally; vertical list at accessibility sizes
                    planCarousel

                    contextualNotice

                    featureBlurb

                    smallPrint

                    restoreRow
                        .padding(.top, 2)
                }
                .padding(.vertical, 14)
                .dynamicTypeSize(.xSmall ... .accessibility5)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 16) }
            .navigationTitle("Get Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
        .task { await store.load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.yellow.opacity(0.9), Color.orange.opacity(0.9)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                Image(systemName: "star.fill")
                    .font(.title2)
                    .foregroundStyle(.black.opacity(0.85))
            }
            Text("AlarmStacks Plus")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Contextual copy based on what triggered the paywall.
    private var contextualNotice: some View {
        let trigger = router.paywallTrigger
        return Group {
            switch trigger {
            case .stacks:
                NoticeBlock(
                    title: "Unlock unlimited stacks",
                    subtitle: "Free plan: up to **2 stacks** (3 steps each)."
                )
            case .steps:
                NoticeBlock(
                    title: "Unlock unlimited steps",
                    subtitle: "Free plan: up to **3 steps per stack** (2 stacks total)."
                )
            case .unknown:
                NoticeBlock(
                    title: "Unlock everything in Plus",
                    subtitle: "Build bigger routines and more stacks."
                )
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Products

    private var planCarousel: some View {
        Group {
            if isAccessibilitySize {
                // Vertical list to give text plenty of room at larger sizes
                LazyVStack(spacing: 12) {
                    ForEach(sortedProducts, id: \.id) { product in
                        PlanCard(
                            product: product,
                            style: style(for: product),
                            isBusy: purchasingID == product.id,
                            badge: badge(for: product),
                            subtitle: subtitle(for: product)
                        ) {
                            Task {
                                purchasingID = product.id
                                defer { purchasingID = nil }
                                await store.purchase(product)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityHint("Double tap to select \(product.displayName)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            } else {
                // Horizontal cards in regular sizes
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(sortedProducts, id: \.id) { product in
                            PlanCard(
                                product: product,
                                style: style(for: product),
                                isBusy: purchasingID == product.id,
                                badge: badge(for: product),
                                subtitle: subtitle(for: product)
                            ) {
                                Task {
                                    purchasingID = product.id
                                    defer { purchasingID = nil }
                                    await store.purchase(product)
                                }
                            }
                            // Fixed width for carousel layout; height grows with content
                            .frame(width: 236)
                            .accessibilityHint("Double tap to select \(product.displayName)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var featureBlurb: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Unlimited stacks", systemImage: "square.stack.3d.up.fill")
            Label("Unlimited steps per stack", systemImage: "list.number")
            Label("Extra themes & accents", systemImage: "paintpalette.fill")
            Label("Future perks & early features", systemImage: "sparkles")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 2)
    }

    private var smallPrint: some View {
        Text("Choose a subscription or lifetime unlock. Manage or cancel in Settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
    }

    private var restoreRow: some View {
        Button {
            Task { await store.restore() }
        } label: {
            Text("Restore Purchases")
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private var sortedProducts: [Product] {
        store.products.sorted { a, b in orderIndex(a) < orderIndex(b) }
    }

    private func orderIndex(_ p: Product) -> Int {
        let id = p.id.lowercased()
        if id.contains(".monthly") { return 0 }
        if id.contains(".yearly") || id.contains(".annual") { return 1 }
        if id.contains(".lifetime") { return 2 }
        return 99
    }

    private func style(for product: Product) -> PlanStyle {
        let id = product.id.lowercased()
        if id.contains(".monthly") {
            return PlanStyle(gradient: [Color.blue, Color.indigo],
                             icon: "calendar", title: "Monthly")
        } else if id.contains(".yearly") || id.contains(".annual") {
            return PlanStyle(gradient: [Color.green, Color.teal],
                             icon: "calendar.circle.fill", title: "Yearly")
        } else if id.contains(".lifetime") {
            return PlanStyle(gradient: [Color.pink, Color.orange],
                             icon: "infinity", title: "Lifetime")
        }
        return PlanStyle(gradient: [Color.gray.opacity(0.6), Color.gray],
                         icon: "questionmark.circle", title: product.displayName)
    }

    private func badge(for product: Product) -> String? {
        let id = product.id.lowercased()
        if id.contains(".yearly") || id.contains(".annual") { return "Best value" }
        if id.contains(".monthly") { return "Flexible" }
        if id.contains(".lifetime") { return "Pay once" }
        return nil
    }

    private func subtitle(for product: Product) -> String {
        let id = product.id.lowercased()
        if id.contains(".monthly") { return "Cancel any time" }
        if id.contains(".yearly") || id.contains(".annual") { return "Save vs monthly" }
        if id.contains(".lifetime") { return "No renewals" }
        return ""
    }
}

// MARK: - Compact notice block that adapts to space

private struct NoticeBlock: View {
    let title: String
    let subtitle: String

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(.init(subtitle)) // allows **bold** segments
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Compact variant if space is tight
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                Text("\(title) — \(subtitle.replacingOccurrences(of: "**", with: ""))")
                    .lineLimit(2)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Card

private struct PlanCard: View {
    let product: Product
    let style: PlanStyle
    let isBusy: Bool
    let badge: String?
    let subtitle: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: style.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(radius: 8, y: 6)

                VStack(alignment: .leading, spacing: 12) {
                    if let badge {
                        Text(badge.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: style.icon)
                            .font(.title2)
                            .foregroundStyle(.primary.opacity(0.9))
                        Text(style.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(product.displayPrice)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.9) // keep prices tidy but readable
                        .lineLimit(1)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // CTA
                    HStack(spacing: 6) {
                        Text(isBusy ? "Purchasing…" : "Continue")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel(isBusy ? "Purchasing" : "Continue")
                    .accessibilityAddTraits(.isButton)
                }
                .padding(18)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.title), \(product.displayPrice)")
    }
}

private struct PlanStyle {
    let gradient: [Color]
    let icon: String
    let title: String
}
