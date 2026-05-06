//
//  CommunityView.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Dedicated community surface for AI insights + player pulse
//  - fed by AppState communityPulse
//  - launched from Arena Community Pulse card
//  - includes production refresh controls
//  - seed controls are DEBUG-only
//  - localized for EN / ES / FR
//

import SwiftUI

struct CommunityView: View {
    @EnvironmentObject private var app: AppState
    @State private var selectedPulseItem: AppState.CommunityPulseItem? = nil
    @State private var isRefreshingPulse: Bool = false
    @State private var showRefreshFlash: Bool = false

    private var isUsingPlaceholderPulse: Bool {
        app.communityPulse.contains { $0.id.hasPrefix("placeholder-") }
    }

    private var hasLivePulse: Bool {
        !app.communityPulse.isEmpty && !isUsingPlaceholderPulse
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let headerTopPadding = max(0, safeTop - 2)
            let headerBandHeight: CGFloat = 54
            let headerTotalHeight = headerTopPadding + headerBandHeight

            ZStack {
                SpaceBackground()
                    .ignoresSafeArea()

                Color.black
                    .ignoresSafeArea()
                    .opacity(0.001)

                CommunityAmbientHaze()
                    .opacity(0.045)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        CommunityTopCommandChrome(topPadding: headerTopPadding)

                        CommunityHeaderBar(
                            title: "community.title".localized,
                            subtitle: subtitleText,
                            onBack: {
                                SpatialAudioManager.shared.play(.uiTap)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    app.setRoute(.hq)
                                }
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, headerTopPadding + 2)
                    }
                    .frame(height: headerTotalHeight)
                    .zIndex(10)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            CommunityControlBar(
                                isUsingPlaceholderPulse: isUsingPlaceholderPulse,
                                isBusy: app.isBusy,
                                isRefreshing: isRefreshingPulse,
                                showRefreshFlash: showRefreshFlash,
                                onSeed: {
                                    SpatialAudioManager.shared.play(.uiTap)
                                    HapticManager.instance.impact(.light)
                                    app.seedCommunityLaunchContent()
                                },
                                onRefresh: {
                                    guard !isRefreshingPulse else { return }

                                    SpatialAudioManager.shared.play(.uiTap)
                                    HapticManager.instance.impact(.light)

                                    isRefreshingPulse = true
                                    showRefreshFlash = false

                                    app.refreshCommunityPulse {
                                        Task { @MainActor in
                                            isRefreshingPulse = false
                                            showRefreshFlash = true

                                            SpatialAudioHooks.victory()
                                            HapticManager.instance.impact(.light)

                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                showRefreshFlash = false
                                            }
                                        }
                                    }
                                }
                            )

                            if let ai = app.latestAIPulse {
                                CommunityFeatureCard(
                                    eyebrow: "community.featured_ai".localized,
                                    title: ai.title,
                                    subtitle: featureSubtitle(for: ai, fallback: "community.ai_insight".localized),
                                    isHighlighted: true
                                )
                            }

                            if let community = app.latestCommunityPulse {
                                CommunityFeatureCard(
                                    eyebrow: "community.signal".localized,
                                    title: community.title,
                                    subtitle: featureSubtitle(
                                        for: community,
                                        fallback: community.authorName.uppercased()
                                    ),
                                    isHighlighted: false
                                )
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                CommunitySectionTitle("community.recent_pulse".localized)

                                if app.communityPulse.isEmpty {
                                    EmptyCommunityPulseCard()
                                } else {
                                    ForEach(app.communityPulse) { item in
                                        CommunityPulseRow(item: item) {
                                            SpatialAudioHooks.tap()
                                            selectedPulseItem = item
                                        }
                                    }
                                }
                            }
                            .communityPanel()

                            Spacer(minLength: 18)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 0)
                        .padding(.bottom, 28)
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .onAppear {
                app.markCommunityPulseRead()
            }
            .sheet(item: $selectedPulseItem) { item in
                CommunityPostDetailSheet(item: item)
                    .environmentObject(app)
            }
        }
    }

    private var subtitleText: String {
        if app.hasUnreadCommunityPulse {
            return "community.subtitle.new".localized
        }
        if isUsingPlaceholderPulse {
            return "community.subtitle.standby".localized
        }
        if hasLivePulse {
            return "community.subtitle.activity".localized
        }
        return "community.subtitle.feed".localized
    }

    private func featureSubtitle(
        for item: AppState.CommunityPulseItem,
        fallback: String
    ) -> String {
        if item.id.hasPrefix("placeholder-") {
            return "community.placeholder_signal".localized
        }

        if item.isAI {
            return item.topic?.uppercased() ?? fallback
        }

        return item.authorName.uppercased()
    }
}

// MARK: - Control Bar

private struct CommunityControlBar: View {
    let isUsingPlaceholderPulse: Bool
    let isBusy: Bool
    let isRefreshing: Bool
    let showRefreshFlash: Bool
    let onSeed: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                CommunitySectionTitle("community.live_controls".localized)

                if isUsingPlaceholderPulse || isRefreshing || showRefreshFlash {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(statusDotScale)
                }

                Spacer()

                Text(statusBadgeText)
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(.black)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(statusBadgeBackgroundColor))
            }

            Text(statusDescriptionText)
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
#if DEBUG
if isUsingPlaceholderPulse {
    Button(action: onSeed) {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(DS.Typography.font(12, weight: .black, design: .default, cappedAt: 14))

            Text(isBusy ? "community.seeding".localized : "community.seed_live_content".localized)
                .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(seedButtonBackground)
        .overlay(seedButtonOverlay)
    }
    .buttonStyle(CommunityPressScaleStyle())
    .disabled(isBusy || isRefreshing)
    .opacity((isBusy || isRefreshing) ? 0.65 : 1.0)
}
#endif

Button(action: onRefresh) {
                    HStack(spacing: 10) {
                        ZStack {
                            if isRefreshing {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: refreshIconName)
                                    .font(DS.Typography.font(13, weight: .black, design: .default, cappedAt: 15))
                            }
                        }
                        .frame(width: 16, height: 16)

                        Text(buttonText)
                            .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                            .tracking(0.8)
                    }
                    .foregroundColor(.white.opacity(0.94))
                    .frame(maxWidth: refreshButtonMaxWidth)
                    .frame(height: 48)
                    .padding(.horizontal, refreshButtonHorizontalPadding)
                    .background(refreshButtonBackground)
                    .overlay(refreshButtonBorder)
                }
                .buttonStyle(CommunityPressScaleStyle())
                .disabled(isBusy || isRefreshing)
                .opacity((isBusy || isRefreshing) ? 0.72 : 1.0)
            }
        }
        .communityPanel()
    }

    private var statusDotColor: Color {
        if showRefreshFlash { return .green }
        if isRefreshing { return .green }
        return .orange
    }

    private var statusDotScale: CGFloat {
        (isRefreshing || showRefreshFlash) ? 1.08 : 1.0
    }

    private var statusBadgeBackgroundColor: Color {
        showRefreshFlash ? Color.green.opacity(0.92) : Color.white.opacity(0.92)
    }

    private var seedButtonBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.orange)
    }

    private var seedButtonOverlay: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        Color.clear,
                        Color.black.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var refreshIconName: String {
        showRefreshFlash ? "checkmark" : "arrow.clockwise"
    }

    private var refreshButtonMaxWidth: CGFloat? {
        isUsingPlaceholderPulse ? .infinity : nil
    }

    private var refreshButtonHorizontalPadding: CGFloat {
        isUsingPlaceholderPulse ? 0 : 16
    }

    private var refreshFillColor: Color {
        showRefreshFlash ? Color.green.opacity(0.18) : Color.white.opacity(0.07)
    }

    private var refreshStrokeColor: Color {
        if showRefreshFlash { return Color.green.opacity(0.30) }
        if isRefreshing { return Color.green.opacity(0.22) }
        return Color.white.opacity(0.10)
    }

    private var refreshButtonBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(refreshFillColor)
    }

    private var refreshButtonBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(refreshStrokeColor, lineWidth: 1)
    }

    private var statusBadgeText: String {
        if showRefreshFlash { return "community.updated".localized }
        if isRefreshing { return "community.sync".localized }
        if isUsingPlaceholderPulse { return "community.placeholder".localized }
        return "community.live".localized
    }

    private var statusDescriptionText: String {
        if showRefreshFlash {
            return "community.refresh.success".localized
        }

        if isRefreshing {
            return "community.refresh.syncing_body".localized
        }

        if isUsingPlaceholderPulse {
            return "community.refresh.seed_body".localized
        }

        return "community.refresh.live_body".localized
    }

    private var buttonText: String {
        if showRefreshFlash { return "community.updated".localized }
        if isRefreshing { return "community.syncing".localized }
        return "community.refresh".localized
    }
}

// MARK: - Feature Card

private struct CommunityFeatureCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(isHighlighted ? .orange.opacity(0.95) : .white.opacity(0.72))
                    .tracking(1.2)

                if isHighlighted {
                    Text("community.goat_intelligence".localized)
                        .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))
                        .foregroundColor(.orange.opacity(0.70))
                        .tracking(1.2)
                }
            }

            Text(title)
                .font(DS.Typography.font(18, weight: .black, design: .rounded, cappedAt: 22))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.58))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isHighlighted ? Color.orange.opacity(0.20) : Color.white.opacity(0.10),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.26), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Pulse Row

private struct CommunityPulseRow: View {
    let item: AppState.CommunityPulseItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isAI ? "sparkles" : "person.2.fill")
                    .foregroundColor(item.isAI ? .orange.opacity(0.95) : .white.opacity(0.84))
                    .frame(width: 20)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(labelText)
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.white.opacity(0.58))
                        .tracking(1.0)

                    Text(item.title)
                        .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))
                        .foregroundColor(.white.opacity(0.94))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(metaText)
                        .font(DS.Typography.font(10, weight: .semibold, design: .rounded, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.46))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.24))
                    .padding(.top, 2)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var labelText: String {
        if item.id.hasPrefix("placeholder-") {
            return "community.placeholder".localized
        }

        return item.isAI
            ? "community.ai_signal".localized
            : "community.player_signal".localized
    }

    private var metaText: String {
        if item.id.hasPrefix("placeholder-") {
            return "community.standby".localized
        }

        if item.isAI {
            return item.topic?.uppercased() ?? "AI"
        }

        return item.authorName.uppercased()
    }
}

// MARK: - Empty State

private struct EmptyCommunityPulseCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("community.empty.title".localized)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.68))
                .tracking(1.0)

            Text("community.empty.body".localized)
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Local Shared UI

private struct CommunityAmbientHaze: View {
    @State private var drift: Bool = false

    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.00),
                Color.white.opacity(0.020),
                Color.white.opacity(0.00)
            ],
            startPoint: drift ? .topLeading : .bottomTrailing,
            endPoint: drift ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9.0).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
    }
}

private struct CommunityTopCommandChrome: View {
    let topPadding: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .background(.ultraThinMaterial.opacity(0.008))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: topPadding + 64)
                .ignoresSafeArea(edges: .top)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.025),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
                .padding(.top, topPadding - 1)
                .padding(.horizontal, 16)

            RadialGradient(
                colors: [
                    Color.orange.opacity(0.022),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 140
            )
            .frame(height: topPadding + 66)
            .allowsHitTesting(false)
        }
    }
}

private struct CommunityHeaderBar: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.2)

                Text(subtitle)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(1.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .foregroundColor(.white.opacity(0.92))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(CommunityPressScaleStyle())
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}

private struct CommunitySectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
            .foregroundColor(.white.opacity(0.74))
            .tracking(1.0)
    }
}

private struct CommunityPressScaleStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.985
    var pressedOpacity: Double = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Detail Sheet

private struct CommunityPostDetailSheet: View {
    @EnvironmentObject private var app: AppState
    let item: AppState.CommunityPulseItem

    @State private var commentText: String = ""

    private var comments: [AppState.CommunityComment] {
        app.commentsForCommunityPost(item.id)
    }

    private var isRefreshing: Bool {
        app.isRefreshingCommunityCommentsByPostID[item.id] ?? false
    }

    private var hasPendingComment: Bool {
        app.hasPendingCommunityComment(for: item.id)
    }

    private var composerDisabled: Bool {
        app.isSubmittingCommunityComment || hasPendingComment
    }

    var body: some View {
        ZStack {
            SpaceBackground()
                .ignoresSafeArea()

            Color.black.opacity(0.001)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    headerPanel
                    fullPostPanel
                    discussionSection
                }
                .padding(16)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            app.startCommunityCommentsListener(for: item.id)
        }
        .onDisappear {
            app.stopCommunityCommentsListener(for: item.id)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.isAI ? "sparkles" : "person.2.fill")
                    .foregroundColor(item.isAI ? .orange.opacity(0.95) : .white.opacity(0.84))

                Text(item.isAI ? "community.ai_signal".localized : "community.player_signal".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.62))
                    .tracking(1.0)
            }

            Text(item.title)
                .font(DS.Typography.font(22, weight: .black, design: .rounded, cappedAt: 28))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailMetaText)
                .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.54))
        }
        .communityPanel()
    }

    private var fullPostPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommunitySectionTitle("community.detail.full_post".localized)

            Text(fullText)
                .font(DS.Typography.font(15, weight: .semibold, design: .rounded, cappedAt: 19))
                .foregroundColor(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: item.isAI ? "sparkles" : "person.crop.circle")
                    .foregroundColor(item.isAI ? .orange.opacity(0.9) : .white.opacity(0.75))

                Text(publishedByText)
                    .font(DS.Typography.font(10, weight: .semibold, design: .rounded, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.50))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
    }

    private var discussionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            CommunitySectionTitle("community.detail.discussion".localized)

            discussionContent

            if hasPendingComment {
                CommunityPendingCommentCard()
            }

            composerSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var discussionContent: some View {
        if isRefreshing {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)

                Text("community.detail.loading_discussion".localized)
                    .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 14))
                    .foregroundColor(.white.opacity(0.60))
            }
        } else if comments.isEmpty {
            Text("community.detail.no_discussion".localized)
                .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 14))
                .foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(comments) { comment in
                    CommunityCommentBubble(comment: comment)
                }
            }
        }
    }

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommunitySectionTitle("community.detail.add_comment".localized)

            HStack(spacing: 10) {
                TextField(
                    composerPlaceholder,
                    text: $commentText,
                    axis: .vertical
                )
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white)
                .tint(.orange)
                .lineLimit(1...4)
                .disabled(composerDisabled)

                Button {
                    let cleaned = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleaned.isEmpty else { return }

                    app.submitCommunityComment(
                        postID: item.id,
                        content: cleaned
                    )

                    commentText = ""
                } label: {
                    if app.isSubmittingCommunityComment {
                        ProgressView()
                            .tint(.orange)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(sendIconColor)
                    }
                }
                .disabled(sendDisabled)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(composerBorder)

            if composerDisabled {
                Text(composerFootnote)
                    .font(DS.Typography.font(10, weight: .semibold, design: .rounded, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sendDisabled: Bool {
        composerDisabled || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendIconColor: Color {
        sendDisabled ? Color.white.opacity(0.25) : Color.orange.opacity(0.95)
    }

    private var composerPlaceholder: String {
        hasPendingComment
            ? "community.detail.comment_pending_placeholder".localized
            : "community.detail.write_comment".localized
    }

    private var composerFootnote: String {
        if app.isSubmittingCommunityComment {
            return "community.detail.submitting_comment".localized
        }

        if hasPendingComment {
            return "community.detail.pending_comment_body".localized
        }

        return ""
    }

    private var composerBorderColor: Color {
        composerDisabled ? Color.orange.opacity(0.16) : Color.white.opacity(0.10)
    }

    private var composerBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(composerBorderColor, lineWidth: 1)
    }

    private var detailMetaText: String {
        if item.isAI {
            return item.topic?.uppercased() ?? "AI"
        }

        return item.authorName.uppercased()
    }

    private var publishedByText: String {
        if item.isAI {
            return "community.detail.published_ai".localized
        }

        return "community.detail.published_by".localized(item.authorName)
    }

    private var fullText: String {
        item.content
    }
}

// MARK: - Comments

private struct CommunityCommentBubble: View {
    let comment: AppState.CommunityComment

    var body: some View {
        VStack(alignment: .leading, spacing: comment.isAI ? 7 : 4) {
            HStack(spacing: 8) {
                if comment.isAI {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.18))
                            .frame(width: 20, height: 20)

                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.orange)
                    }
                }

                Text(comment.isAI ? "TRIVIA GOAT" : comment.authorName.uppercased())
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(comment.isAI ? .orange.opacity(0.92) : .white.opacity(0.52))
                    .tracking(0.9)

                if comment.isAI {
                    Text("community.goat_ai".localized)
                        .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))
                        .foregroundColor(.black)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.95))
                        )
                }
            }

            Text(comment.content)
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(comment.isAI ? .white.opacity(0.96) : .white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(comment.isAI ? 12 : 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(comment.isAI ? Color.orange.opacity(0.10) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    comment.isAI ? Color.orange.opacity(0.28) : Color.white.opacity(0.06),
                    lineWidth: comment.isAI ? 1.5 : 1
                )
        )
    }
}

private struct CommunityPendingCommentCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("community.detail.comment_submitted".localized)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(0.9)

            Text("community.detail.comment_pending_body".localized)
                .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 14))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }
}

private extension View {
    func communityPanel() -> some View {
        self
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}
