//
//  PaywallView.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import SwiftUI
import StoreKit
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = Store.shared
    @State private var purchasingID: String?

    // Support / diagnostics state
    @State private var diagText: String = ""
    @State private var showingDiag = false
    @State private var shareItems: [Any] = []
    @State private var showingShare = false
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                        .padding(.top, 8)

                    // If products didn’t load, show the diagnostics card inline.
                    if store.products.isEmpty {
                        ProductUnavailableCard()
                            .padding(.top, 6)
                            .padding(.bottom, 10)
                    } else {
                        planCarousel
                            .padding(.top, 6)
                            .padding(.bottom, 10)
                    }

                    featureBlurb
                        .padding(.top, 4)

                    smallPrint

                    restoreRow
                        .padding(.top, 2)
                }
                .padding(.vertical, 18)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
            .navigationTitle("Get Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Support menu is always available, even if products load.
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            Task {
                                diagText = await store.storeDiagnostics()
                                showingDiag = true
                            }
                        } label: {
                            Label("Diagnostics", systemImage: "doc.text.magnifyingglass")
                        }

                        Button {
                            Task {
                                let text = await store.storeDiagnostics()
                                if let url = writeDiagnosticsFile(text) {
                                    shareItems = [url]
                                    showingShare = true
                                }
                            }
                        } label: {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            Task {
                                isRefreshing = true
                                await store.load()
                                isRefreshing = false
                            }
                        } label: {
                            Label(isRefreshing ? "Refreshing…" : "Refresh products",
                                  systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
                    } label: {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .alert("Store Diagnostics", isPresented: $showingDiag, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(diagText.isEmpty ? "No details." : diagText).textSelection(.enabled)
            })
            .sheet(isPresented: $showingShare) {
                ActivityView(items: shareItems).ignoresSafeArea()
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
            HStack(spacing: 18) {
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
                    .frame(width: 236, height: 164)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    private var featureBlurb: some View {
        VStack(spacing: 14) {
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
            .padding(.horizontal, 28)
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

    /// Writes a timestamped diagnostics text file to the temp directory.
    private func writeDiagnosticsFile(_ text: String) -> URL? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = fmt.string(from: Date())
        let name = "AlarmStacks-Diagnostics-\(stamp).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Unavailable / Diagnostics fallback card

private struct ProductUnavailableCard: View {
    @StateObject private var store = Store.shared
    @State private var diag: String = ""
    @State private var showingDiag = false
    @State private var isRefreshing = false
    @State private var shareItems: [Any] = []
    @State private var showingShare = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cart.badge.exclamationmark").font(.largeTitle)
            Text("Products unavailable")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("We couldn’t load Plus plans from the App Store on this device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(isRefreshing ? "Refreshing…" : "Try again") {
                    Task {
                        isRefreshing = true
                        await store.load()
                        isRefreshing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)

                Button("Diagnostics") {
                    Task {
                        diag = await store.storeDiagnostics()
                        showingDiag = true
                    }
                }
                .buttonStyle(.bordered)

                Button("Share…") {
                    Task {
                        let text = await store.storeDiagnostics()
                        if let url = writeDiagnosticsFile(text) {
                            shareItems = [url]
                            showingShare = true
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            if let err = store.lastProductFetchError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
        .alert("Store Diagnostics", isPresented: $showingDiag, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(diag.isEmpty ? "No details." : diag).textSelection(.enabled)
        })
        .sheet(isPresented: $showingShare) {
            ActivityView(items: shareItems).ignoresSafeArea()
        }
    }

    private func writeDiagnosticsFile(_ text: String) -> URL? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = fmt.string(from: Date())
        let name = "AlarmStacks-Diagnostics-\(stamp).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
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
                .padding(18)
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

#if canImport(UIKit)
// Native share sheet bridge
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
