//
//  Store.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import StoreKit
import Combine

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var isPlus: Bool {
        didSet { UserDefaults.standard.set(isPlus, forKey: "store.isPlus") }
    }

    @Published private(set) var products: [Product] = []

    // Replace with your real product IDs (ensure they exactly match the StoreKit Configuration or App Store Connect).
    private let productIDs = [
        "com.hodlsimulator.alarmstacks.plus.monthly",
        "com.hodlsimulator.alarmstacks.plus.yearly",
        "com.hodlsimulator.alarmstacks.plus.lifetime"
    ]

    private var updatesTask: Task<Void, Never>?

    private init() {
        self.isPlus = UserDefaults.standard.bool(forKey: "store.isPlus")
    }

    deinit {
        updatesTask?.cancel()
    }

    func load() async {
        do {
            products = try await Product.products(for: productIDs)
        } catch {
            print("StoreKit load error: \(error)")
        }

        // Listen for transaction updates once.
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                guard let self else { return }
                for await result in Transaction.updates {
                    if let tx = self.checkVerified(result) {
                        await self.updateEntitlements(tx)
                        await tx.finish()
                    }
                }
            }
        }

        // Seed from current entitlements.
        for await ent in Transaction.currentEntitlements {
            if let tx = checkVerified(ent) {
                await updateEntitlements(tx)
            }
        }
    }

    func purchase(_ product: Product) async {
        do {
            let res = try await product.purchase()
            switch res {
            case .success(let verification):
                if let tx = checkVerified(verification) {
                    await updateEntitlements(tx)
                    await tx.finish()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            print("Restore failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func updateEntitlements(_ tx: Transaction) async {
        // For simplicity, any active auto-renewable or non-consumable unlocks Plus.
        switch tx.productType {
        case .autoRenewable, .nonConsumable:
            isPlus = true
        default:
            break
        }

        // If nothing is currently entitled, ensure flag is false.
        var hasPlus = false
        for await ent in Transaction.currentEntitlements {
            if let e = checkVerified(ent) {
                if e.productType == .autoRenewable || e.productType == .nonConsumable {
                    hasPlus = true
                }
            }
        }
        if !hasPlus { isPlus = false }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .unverified: return nil
        case .verified(let safe): return safe
        }
    }
}
