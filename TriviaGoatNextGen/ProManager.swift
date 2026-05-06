//
//  ProManager.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-03-04.
//

import Foundation
import Combine
import StoreKit

@MainActor
final class ProManager: ObservableObject {

    static let shared = ProManager()

    // MARK: - Notifications

    static let entitlementDidChangeNotification = Notification.Name("ProManager.entitlementDidChange")

    // MARK: - Entitlement Snapshot

    struct EntitlementSnapshot: Equatable {
        let isPro: Bool
        let proTier: String?
        let proStartedAt: Date?
        let proExpiresAt: Date?
    }

    // MARK: - Published State

    @Published private(set) var isPro: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading: Bool = false

    // MARK: - Product IDs

    private let productIDs: Set<String> = [
        "com.triviagoat.pro.monthly",
        "com.triviagoat.pro.yearly"
    ]

    // MARK: - StoreKit Entitlement State

    private var storeKitIsPro: Bool = false
    private var storeKitProTier: String? = nil
    private var storeKitProStartedAt: Date? = nil
    private var storeKitProExpiresAt: Date? = nil

    private var didBoot: Bool = false
    private var updatesTask: Task<Void, Never>?

    #if DEBUG
    private var debugObserver: NSObjectProtocol?
    #endif

    private init() {}

    deinit {
        updatesTask?.cancel()

        #if DEBUG
        if let debugObserver {
            NotificationCenter.default.removeObserver(debugObserver)
        }
        #endif
    }

    // MARK: - Boot

    func boot() async {
        guard !didBoot else {
            await refreshEntitlement()
            return
        }

        didBoot = true

        #if DEBUG
        debugObserver = NotificationCenter.default.addObserver(
            forName: TGDebugProOverride.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                let didChange = self.applyEffectiveEntitlement()
                if didChange {
                    self.postEntitlementDidChange()
                }
            }
        }
        #endif

        listenForTransactionsIfNeeded()

        await loadProducts()
        await refreshEntitlement()
    }

    // MARK: - Products

    func loadProducts() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await Product.products(for: Array(productIDs))

            products = fetched.sorted { a, b in
                let aRank = a.id.contains("yearly") ? 0 : 1
                let bRank = b.id.contains("yearly") ? 0 : 1

                if aRank != bRank {
                    return aRank < bRank
                }

                return a.displayPrice < b.displayPrice
            }
        } catch {
            products = []
            print("⚠️ Failed to load products:", error)
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlement()

            case .pending:
                break

            case .userCancelled:
                break

            @unknown default:
                break
            }
        } catch {
            print("⚠️ Purchase failed:", error)
        }
    }

    // MARK: - Restore

    func restore() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
        } catch {
            print("⚠️ AppStore.sync failed:", error)
        }

        await refreshEntitlement()
    }

    // MARK: - Entitlement

    func refreshEntitlement() async {
        var hasPro = false
        var bestTier: String? = nil
        var bestStartedAt: Date? = nil
        var bestExpiresAt: Date? = nil

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIDs.contains(transaction.productID) else { continue }

            hasPro = true

            let tier: String = transaction.productID.contains("yearly")
                ? "pro_yearly"
                : "pro_monthly"

            let candidateExpiry = transaction.expirationDate ?? .distantFuture
            let existingExpiry = bestExpiresAt ?? .distantPast

            if bestTier == nil || candidateExpiry > existingExpiry {
                bestTier = tier
                bestStartedAt = transaction.purchaseDate
                bestExpiresAt = transaction.expirationDate
            }
        }

        let previousSnapshot = effectiveSnapshot()

        storeKitIsPro = hasPro
        storeKitProTier = hasPro ? bestTier : nil
        storeKitProStartedAt = hasPro ? bestStartedAt : nil
        storeKitProExpiresAt = hasPro ? bestExpiresAt : nil

        _ = applyEffectiveEntitlement()

        let nextSnapshot = effectiveSnapshot()

        if previousSnapshot != nextSnapshot {
            postEntitlementDidChange()
        }
    }

    func currentEntitlementSnapshot() async -> EntitlementSnapshot {
        await refreshEntitlement()
        return effectiveSnapshot()
    }

    private func effectiveSnapshot() -> EntitlementSnapshot {
        EntitlementSnapshot(
            isPro: isPro,
            proTier: resolvedProTier(),
            proStartedAt: resolvedProStartedAt(),
            proExpiresAt: resolvedProExpiresAt()
        )
    }

    @discardableResult
    private func applyEffectiveEntitlement() -> Bool {
        let previous = isPro

        #if DEBUG
        isPro = storeKitIsPro || TGDebugProOverride.isPro
        #else
        isPro = storeKitIsPro
        #endif

        return previous != isPro
    }

    private func resolvedProTier() -> String? {
        #if DEBUG
        if TGDebugProOverride.isPro, !storeKitIsPro {
            return "debug_pro"
        }
        #endif

        return isPro ? (storeKitProTier ?? "pro") : nil
    }

    private func resolvedProStartedAt() -> Date? {
        #if DEBUG
        if TGDebugProOverride.isPro, !storeKitIsPro {
            return nil
        }
        #endif

        return isPro ? storeKitProStartedAt : nil
    }

    private func resolvedProExpiresAt() -> Date? {
        #if DEBUG
        if TGDebugProOverride.isPro, !storeKitIsPro {
            return nil
        }
        #endif

        return isPro ? storeKitProExpiresAt : nil
    }

    private func postEntitlementDidChange() {
        NotificationCenter.default.post(
            name: Self.entitlementDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Transaction Listener

    private func listenForTransactionsIfNeeded() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            guard let self else { return }

            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }

                await transaction.finish()
                await self.refreshEntitlement()
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe

        case .unverified(_, let error):
            throw error
        }
    }
}
