//
//  PaywallView.swift
//  TriviaGoatNextGen
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var pro: ProManager

    @State private var selectedProductID: String? = nil
    @State private var showError: Bool = false
    @State private var errorText: String = ""
    @State private var float: Bool = false
    @State private var isPurchasing: Bool = false
    @State private var isRestoring: Bool = false

    var body: some View {
        ZStack {
            SpaceBackground()

            VStack(spacing: 18) {
                Spacer(minLength: 18)

                heroSection
                plansSection
                primaryCTA
                footerSection

                Spacer(minLength: 18)
            }

            if isPurchasing || isRestoring {
                processingOverlay
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .alert("paywall.error.title".localized, isPresented: $showError) {
            Button("common.ok".localized, role: .cancel) { }
        } message: {
            Text(errorText)
        }
        .onAppear {
            loadProductsIfNeeded()
        }
        .onChange(of: pro.products) { _, _ in
            if selectedProductID == nil {
                selectedProductID = preferredDefaultProductID()
            }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image("tg_mascot")
                .resizable()
                .scaledToFit()
                .frame(height: 150)
                .offset(y: float ? -5 : 5)
                .padding(.bottom, 12)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                        float.toggle()
                    }
                }

            Text("paywall.eyebrow".localized)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.orange)
                .tracking(4)

            Text("paywall.title".localized)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)

            Text("paywall.body".localized)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.70))
                .multilineTextAlignment(.center)

            if let product = selectedProduct(),
               let trial = trialLine(for: product) {
                Text(trial)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.80))
                    .tracking(1.5)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
    }

    private var plansSection: some View {
        Group {
            if pro.products.isEmpty {
                Text(pro.isLoading ? "paywall.loading_offers".localized : "paywall.offers_unavailable".localized)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedProducts, id: \.id) { product in
                        PaywallProductRow(
                            title: planTitle(for: product),
                            price: product.displayPrice,
                            savings: savingsLine(for: product),
                            isSelected: selectedProductID == product.id,
                            isBest: isYearly(product),
                            onTap: {
                                HapticManager.instance.impact(.light)
                                selectedProductID = product.id
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var primaryCTA: some View {
        VStack(spacing: 10) {
            Button {
                HapticManager.instance.impact(.heavy)
                Task { await purchaseSelected() }
            } label: {
                Text(primaryButtonTitle)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .shadow(color: .orange.opacity(0.4), radius: 20, y: 8)
            .padding(.horizontal, 20)
            .disabled(pro.products.isEmpty || pro.isLoading || isPurchasing || isRestoring)

            Text("paywall.renewal_note".localized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private var footerSection: some View {
        HStack(spacing: 20) {
            Button {
                Task { await restore() }
            } label: {
                Text(isRestoring ? "paywall.restoring".localized : "paywall.restore".localized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || isRestoring)

            Text("•")
                .foregroundColor(.white.opacity(0.25))

            Button {
                app.setRoute(.hq)
            } label: {
                Text("paywall.not_now".localized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || isRestoring)
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(.orange)
                    .scaleEffect(1.2)

                Text(isRestoring ? "paywall.overlay.restoring".localized : "paywall.overlay.confirming".localized)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.4)

                Text("paywall.overlay.body".localized)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Purchase / Restore

    private func purchaseSelected() async {
        guard !isPurchasing, !isRestoring else { return }
        guard let product = selectedProduct() else { return }

        isPurchasing = true
        defer { isPurchasing = false }

        await pro.purchase(product)

        let becamePro = await waitForProEntitlement()

        guard becamePro else {
            errorText = "paywall.error.confirm_failed".localized
            showError = true
            return
        }

        await MainActor.run {
            app.triggerEntitlementRefreshAfterPurchase()
        }

        await app.syncEntitlementFromStoreKit(force: true)

        await MainActor.run {
            app.completeProUpgradeFlow()
        }
    }

    private func restore() async {
        guard !isPurchasing, !isRestoring else { return }

        isRestoring = true
        defer { isRestoring = false }

        await pro.restore()

        let becamePro = await waitForProEntitlement()

        guard becamePro else {
            errorText = "paywall.error.no_restore".localized
            showError = true
            return
        }

        await MainActor.run {
            app.triggerEntitlementRefreshAfterRestore()
        }

        await app.syncEntitlementFromStoreKit(force: true)

        await MainActor.run {
            _ = app.openGlobalBattleIfEnabled()
        }
    }

    private func waitForProEntitlement() async -> Bool {
        for _ in 0..<10 {
            if pro.isPro { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        await pro.restore()

        for _ in 0..<6 {
            if pro.isPro { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        return pro.isPro
    }

    // MARK: - Helpers

    private func loadProductsIfNeeded() {
        if pro.products.isEmpty && !pro.isLoading {
            Task { await pro.loadProducts() }
        }

        if selectedProductID == nil {
            selectedProductID = preferredDefaultProductID()
        }
    }

    private var sortedProducts: [Product] {
        pro.products.sorted {
            (isYearly($0) ? 0 : 1) < (isYearly($1) ? 0 : 1)
        }
    }

    private func selectedProduct() -> Product? {
        if let selectedProductID,
           let product = pro.products.first(where: { $0.id == selectedProductID }) {
            return product
        }

        return pro.products.first(where: { isYearly($0) }) ?? pro.products.first
    }

    private func preferredDefaultProductID() -> String? {
        pro.products.first(where: { isYearly($0) })?.id ?? pro.products.first?.id
    }

    private func isYearly(_ product: Product) -> Bool {
        let id = product.id.lowercased()
        return id.contains("year") || id.contains("annual")
    }

    private func planTitle(for product: Product) -> String {
        isYearly(product)
            ? "paywall.plan.yearly".localized
            : "paywall.plan.monthly".localized
    }

    private func trialLine(for product: Product) -> String? {
        guard
            let subscription = product.subscription,
            let intro = subscription.introductoryOffer,
            intro.paymentMode == .freeTrial
        else { return nil }

        return "paywall.trial_line".localized
    }

    private func savingsLine(for product: Product) -> String? {
        guard isYearly(product),
              let monthly = pro.products.first(where: { !isYearly($0) })
        else { return nil }

        let yearly = (product.price as NSDecimalNumber).doubleValue
        let monthlyPrice = (monthly.price as NSDecimalNumber).doubleValue
        let yearlyFromMonthly = monthlyPrice * 12

        guard yearlyFromMonthly > 0, yearly < yearlyFromMonthly else { return nil }

        let pct = Int((((yearlyFromMonthly - yearly) / yearlyFromMonthly) * 100).rounded())
        return pct >= 5
            ? String(format: "paywall.savings".localized, pct)
            : nil
    }

    private var primaryButtonTitle: String {
        if isPurchasing { return "paywall.confirming".localized }
        if isRestoring { return "paywall.restoring".localized }
        if pro.isLoading { return "paywall.loading".localized }
        return "paywall.cta".localized
    }
}

// MARK: - Product Row

private struct PaywallProductRow: View {
    let title: String
    let price: String
    let savings: String?
    let isSelected: Bool
    let isBest: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .orange : .white.opacity(0.35))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text(price)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))

                    if let savings {
                        Text(savings)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer()

                if isBest {
                    Text("paywall.best".localized)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(Color.white))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(isSelected ? 0.20 : 0.10))
            )
        }
        .buttonStyle(.plain)
        .pressScale()
    }
}
