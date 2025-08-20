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

    // MARK: - Products you sell (exact IDs from App Store Connect)
    // Two auto-renew subscriptions (monthly, yearly) + one lifetime non-consumable.
    private let productIDs: [String] = [
        "com.hodlsimulator.alarmstacks.plus.monthly",
        "com.hodlsimulator.alarmstacks.plus.yearly",
        "com.hodlsimulator.alarmstacks.plus.lifetime"
    ]

    // MARK: - State
    @Published private(set) var isPlus: Bool {
        didSet { UserDefaults.standard.set(isPlus, forKey: Self.plusKey) }
    }
    @Published private(set) var products: [Product] = []

    private static let plusKey = "store.isPlus"
    private var updatesTask: Task<Void, Never>?
    private let log = Logger(subsystem: "AlarmStacks", category: "Store")

    private init() {
        self.isPlus = UserDefaults.standard.bool(forKey: Self.plusKey)
    }

    deinit { updatesTask?.cancel() }

    // Call once on app launch; safe to call multiple times.
    func configureAtLaunch() async {
        await loadProducts()
        startObservingTransactionsIfNeeded()
        await recomputeEntitlementsFromCurrent()
    }

    // Retained for views that already call `load()` (idempotent).
    func load() async {
        await loadProducts()
        startObservingTransactionsIfNeeded()
        await recomputeEntitlementsFromCurrent()
    }

    // MARK: - Product fetch

    private func loadProducts() async {
        do {
            let ids = productIDs
            let fetched = try await Product.products(for: ids)
            self.products = fetched

            let idsList = fetched.map(\.id).joined(separator: ", ")
            log.info("SK2 fetched \(fetched.count, privacy: .public) products: \(idsList, privacy: .public)")

            if fetched.isEmpty {
                log.warning("SK2 returned ZERO products. Check ASC: IDs, Agreements/Tax/Banking, IAP status=Approved, territories, and that the TestFlight build targets the correct app record.")
            }
        } catch {
            log.error("SK2 product fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    // Handy one-liner you can call from anywhere for diagnostics.
    func debugFetchProducts() {
        Task { [ids = productIDs] in
            do {
                let products = try await Product.products(for: ids)
                let idsList = products.map(\.id).joined(separator: ", ")
                log.info("DEBUG fetch -> \(products.count, privacy: .public) products: \(idsList, privacy: .public)")
            } catch {
                log.error("DEBUG fetch error: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Purchases & restore

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
                await recomputeEntitlementsFromCurrent() // derive from the authoritative stream
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
            log.error("Purchase failed for \(product.id, privacy: .public): \(String(describing: error), privacy: .public)")
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

    // MARK: - Transaction updates / entitlements

    private func startObservingTransactionsIfNeeded() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                await self.handle(transactionResult: result)
            }
        }
        log.info("Started observing Transaction.updates.")
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard let tx = checkVerified(transactionResult) else {
            log.error("Transaction update unverified.")
            return
        }
        log.info("Transaction update for productID=\(tx.productID, privacy: .public), type=\(String(describing: tx.productType), privacy: .public)")
        await recomputeEntitlementsFromCurrent()
        await tx.finish()
    }

    private func recomputeEntitlementsFromCurrent() async {
        var plus = false
        let idSet = Set(productIDs)
        for await result in Transaction.currentEntitlements {
            guard let t = checkVerified(result) else { continue }
            guard idSet.contains(t.productID) else { continue } // only your Plus products count
            guard t.revocationDate == nil, t.revocationReason == nil else { continue } // revoked = not entitled
            // Active auto-renew subscription or non-consumable lifetime
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

    // MARK: - Verification helper

    private func checkVerified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .unverified(_, let error):
            // `error` is non-optional; just log it.
            log.error("Verification failed: \(String(describing: error), privacy: .public)")
            return nil
        case .verified(let safe):
            return safe
        }
    }
}
