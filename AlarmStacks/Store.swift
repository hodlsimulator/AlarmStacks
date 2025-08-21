//
//  Store.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import StoreKit
import Combine
import OSLog

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    // MARK: - Published state

    private static let plusKey = "store.isPlus"

    @Published private(set) var isPlus: Bool {
        didSet { UserDefaults.standard.set(isPlus, forKey: Self.plusKey) }
    }

    @Published private(set) var products: [Product] = []

    /// Last fetch error or "Fetched 0 products" to surface issues on tester devices.
    @Published private(set) var lastProductFetchError: String?

    // MARK: - Config

    /// Exact product IDs in App Store Connect (case sensitive).
    private let productIDs: [String] = [
        "com.hodlsimulator.alarmstacks.plus.monthly",
        "com.hodlsimulator.alarmstacks.plus.yearly",
        "com.hodlsimulator.alarmstacks.plus.lifetime"
    ]

    private var updatesTask: Task<Void, Never>?
    private let log = Logger(subsystem: "AlarmStacks", category: "Store")

    // MARK: - Lifecycle

    private init() {
        self.isPlus = UserDefaults.standard.bool(forKey: Self.plusKey)
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Public API

    /// Call once on launch (safe to call multiple times).
    func configureAtLaunch() async {
        await loadProducts()
        startObservingTransactionsIfNeeded()
        await recomputeEntitlementsFromCurrent()
    }

    /// Backwards-compatible alias for existing callers.
    func load() async { await configureAtLaunch() }

    /// Manual refresh (used by the paywall "Try again" button).
    func refreshProducts() async { await loadProducts() }

    func purchase(_ product: Product) async {
        log.info("Attempting purchase for \(product.id, privacy: .public)")
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let tx = checkVerified(verification) else {
                    log.error("Purchase unverified for \(product.id, privacy: .public)")
                    return
                }
                await recomputeEntitlementsFromCurrent()
                await tx.finish()
                log.info("Purchase completed for \(product.id, privacy: .public)")
            case .userCancelled:
                log.info("Purchase cancelled for \(product.id, privacy: .public)")
            case .pending:
                log.info("Purchase pending for \(product.id, privacy: .public)")
            @unknown default:
                log.error("Purchase returned unknown result for \(product.id, privacy: .public)")
            }
        } catch {
            log.error("Purchase failed: \(String(describing: error), privacy: .public)")
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            log.info("AppStore.sync() requested.")
            await recomputeEntitlementsFromCurrent()
        } catch {
            log.error("Restore failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// On-device diagnostics you can show in UI.
    func storeDiagnostics() async -> String {
        var lines: [String] = []
        lines.append("products.count=\(products.count)")
        lines.append("lastError=\(lastProductFetchError ?? "none")")

        // ✅ AppTransaction.shared is async (and throws) → use try? await
        let environment: String = await {
            if let res = try? await AppTransaction.shared,
               case let .verified(atx) = res {
                return String(describing: atx.environment)
            }
            return "unknown"
        }()
        lines.append("appTx.environment=\(environment)")

        // ✅ Storefront.current is synchronous & optional on your SDK → no await
        if let sf = await StoreKit.Storefront.current {
            let sfID = sf.id
            let sfCC = sf.countryCode
            lines.append("storefront.id=\(sfID) country=\(sfCC)")
        } else {
            lines.append("storefront.id=unknown country=unknown")
        }

        lines.append("productIDs=\(productIDs.joined(separator: ", "))")
        let bid = Bundle.main.bundleIdentifier ?? "nil"
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "nil"
        let bld = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "nil"
        lines.append("bundleID=\(bid) version=\(ver) (\(bld))")

        return lines.joined(separator: "\n")
    }

    /// Extra debug fetch you can trigger from anywhere.
    func debugFetchProducts() {
        Task { [ids = productIDs] in
            do {
                let prods = try await Product.products(for: ids)
                let idsList = prods.map(\.id).joined(separator: ", ")
                log.info("DEBUG fetch -> \(prods.count, privacy: .public) products: \(idsList, privacy: .public)")
            } catch {
                log.error("DEBUG fetch error: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Private

    /// Fetch products and capture a friendly error string for UI.
    private func loadProducts() async {
        do {
            let fetched = try await Product.products(for: productIDs)
            self.products = fetched
            self.lastProductFetchError = fetched.isEmpty ? "Fetched 0 products" : nil

            if fetched.isEmpty {
                log.warning("SK2 fetched ZERO products.")
            } else {
                let list = fetched.map(\.id).joined(separator: ", ")
                log.info("SK2 fetched \(fetched.count, privacy: .public) products: \(list, privacy: .public)")
            }
        } catch {
            self.products = []
            self.lastProductFetchError = String(describing: error)
            log.error("SK2 product fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Swift 6-safe observer: runs on the main actor to mutate state.
    private func startObservingTransactionsIfNeeded() {
        guard updatesTask == nil else { return }
        updatesTask = Task { @MainActor in
            log.info("Started observing Transaction.updates.")
            for await result in Transaction.updates {
                switch result {
                case .verified(let tx):
                    log.info("Transaction update for productID=\(tx.productID, privacy: .public)")
                    await recomputeEntitlementsFromCurrent()
                    await tx.finish()
                case .unverified(_, let error):
                    log.error("Transaction update unverified: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Single source of truth for entitlement flag.
    private func recomputeEntitlementsFromCurrent() async {
        var plus = false
        let idSet = Set(productIDs)

        for await result in Transaction.currentEntitlements {
            guard let t = checkVerified(result) else { continue }
            guard idSet.contains(t.productID) else { continue }
            guard t.revocationDate == nil, t.revocationReason == nil else { continue }

            if t.productType == .autoRenewable || t.productType == .nonConsumable {
                plus = true
                break
            }
        }

        if self.isPlus != plus {
            self.isPlus = plus
            log.info("Entitlements recomputed → Plus=\(plus ? "true" : "false", privacy: .public)")
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .unverified(_, let error):
            log.error("Verification failed: \(String(describing: error), privacy: .public)")
            return nil
        case .verified(let safe):
            return safe
        }
    }
}
