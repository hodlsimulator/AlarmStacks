//
//  StoreKitLocalTesting.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

#if DEBUG
import Foundation

#if canImport(StoreKitTest)
import StoreKitTest
#endif

enum StoreKitLocalTesting {

    #if canImport(StoreKitTest)
    @available(iOS 14.0, *)
    private static var session: SKTestSession?

    static func activateIfPossible() {
        guard #available(iOS 14.0, *) else { return }
        guard session == nil else { return }
        guard let url = Bundle.main.url(forResource: "StoreKit", withExtension: "storekit") else {
            print("StoreKitLocalTesting: StoreKit.storekit not found in bundle")
            return
        }
        do {
            let s = try SKTestSession(configurationFileURL: url)
            s.resetToDefaultState()
            s.clearTransactions()
            s.disableDialogs = false       // show purchase sheets
            s.askToBuyEnabled = false
            session = s
            print("StoreKitLocalTesting: SKTestSession active (\(url.lastPathComponent))")
        } catch {
            print("StoreKitLocalTesting: failed to start session: \(error)")
        }
    }
    #else
    // Fallback when StoreKitTest isn't available on this SDK/target.
    static func activateIfPossible() {
        // no-op
        print("StoreKitLocalTesting: StoreKitTest module not available; skipping local session")
    }
    #endif
}
#endif
