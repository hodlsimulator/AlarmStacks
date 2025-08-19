//
//  PaywallView.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = Store.shared
    @State private var purchasingID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {              // ← more global spacing
                    header
                        .padding(.top, 8)

                    planCarousel                       // ← cards first; fully visible
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                    featureBlurb
                        .padding(.top, 4)

                    smallPrint

                    restoreRow
                        .padding(.top, 2)
                }
                .padding(.vertical, 18)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) } // more bottom air
            .navigationTitle("Get Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await store.load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.yellow.opacity(0.9), Color.orange.opacity(0.9)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Image(systemName: "star.fill")
                    .font(.title)
                    .foregroundStyle(.black.opacity(0.85))
            }
            Text("AlarmStacks Plus")
                .font(.title2.weight(.semibold))
        }
    }

    private var planCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {                 // ← wider gap between cards
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
                    .frame(width: 236, height: 164) // slightly compact height
                }
            }
            .padding(.horizontal, 24)             // ← more side padding
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    private var featureBlurb: some View {
        VStack(spacing: 14) {                     // ← looser spacing in blurb
            Text("Unlock more theme colours and future premium features.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 10) {
                Label("Unlimited stacks (free up to 2)", systemImage: "square.stack.3d.up.fill")
                Label("Extra themes & accents", systemImage: "paintpalette.fill")
                Label("Future perks & early features", systemImage: "sparkles")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }

    private var smallPrint: some View {
        Text("Subscriptions renew automatically. You can cancel any time in Settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)             // ← more margins around small text
    }

    private var restoreRow: some View {
        Button {
            Task { try? await AppStore.sync() }
        } label: {
            Text("Restore Purchases")
                .font(.callout.weight(.semibold))
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
        if id.contains(".lifetime") { return 2 }   // lifetime last
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

                VStack(alignment: .leading, spacing: 12) {     // ← more inner spacing
                    if let badge {
                        Text(badge.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.primary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: style.icon)
                            .font(.title2)
                            .foregroundStyle(.primary.opacity(0.9))
                        Text(style.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    Text(product.displayPrice)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.primary.opacity(0.85))
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Text(isBusy ? "Purchasing…" : "Continue")
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(18)                                   // ← a bit more padding inside card
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.title), \(product.displayPrice)")
    }
}

private struct PlanStyle {
    let gradient: [Color]
    let icon: String
    let title: String
}
