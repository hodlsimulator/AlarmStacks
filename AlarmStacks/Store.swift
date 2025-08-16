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

    @Published private(set) var isPlus = false
    @Published private(set) var products: [Product] = []

    // Replace with your real product IDs.
    private let productIDs = [
        "com.hodlsimulator.alarmstacks.plus.monthly",
        "com.hodlsimulator.alarmstacks.plus.yearly",
        "com.hodlsimulator.alarmstacks.plus.lifetime"
    ]

    private init() { }

    func load() async {
        do { products = try await Product.products(for: productIDs) }
        catch { print("StoreKit load error: \(error)") }

        // Listen for updates.
        for await result in Transaction.updates {
            if let tx = checkVerified(result) { await updateEntitlements(tx) }
        }
        // Seed from current entitlements.
        for await ent in Transaction.currentEntitlements {
            if let tx = checkVerified(ent) { await updateEntitlements(tx) }
        }
    }

    func purchase(_ product: Product) async {
        do {
            let res = try await product.purchase()
            if case .success(let verification) = res, let tx = checkVerified(verification) {
                await updateEntitlements(tx)
                await tx.finish()
            }
        } catch { print("Purchase failed: \(error)") }
    }

    private func updateEntitlements(_ tx: Transaction) async {
        switch tx.productType {
        case .autoRenewable, .nonConsumable:
            isPlus = true
        default: break
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .unverified: return nil
        case .verified(let safe): return safe
        }
    }
}
