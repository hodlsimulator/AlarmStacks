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
            VStack(spacing: 16) {
                Image(systemName: "star.circle.fill").font(.system(size: 48)).foregroundStyle(.yellow)
                Text("AlarmStacks Plus").font(.title2.weight(.semibold))
                Text("Unlock extra theme colours and future premium features.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Products
                VStack(spacing: 10) {
                    ForEach(store.products, id: \.id) { product in
                        Button {
                            purchasingID = product.id
                            Task {
                                await store.purchase(product)
                                purchasingID = nil
                                if store.isPlus { dismiss() }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(product.displayName).font(.headline)
                                    Text(product.displayPrice).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if purchasingID == product.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .navigationTitle("Get Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await store.load() }
        }
    }
}
