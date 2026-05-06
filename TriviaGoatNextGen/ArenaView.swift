//
//  ArenaView.swift
//  TriviaGoatNextGen
//

import SwiftUI
import FirebaseAuth

struct ArenaView: View {
    @EnvironmentObject private var app: AppState

    @State private var trainingTopicInput: String = ""
    @State private var showNoResultsAlert: Bool = false

    @State private var showReentryMoment: Bool = false
    @State private var lastSeenClaimKey: String = ""
    @State private var reentryXP: Int = 0
    @State private var reentryTick: Int = 0

    private let hqBGMName: String = "tg_hq_bgm"
    private let hqBGMVolume: Float = 0.32

    var body: some View {
        GeometryReader { geo in
            let appRef = app

            let proEnabled: Bool = {
                #if DEBUG
                if TGDebugProOverride.isPro { return true }
                #endif
                return app.profile.isPro || ProManager.shared.isPro
            }()

            let gateText = proEnabled ? "∞" : "common.pro".localized
            let globalBattleIsUnlocked = appRef.canAccessGlobalBattle

            let missionSnap = DailyMission.snapshot(
                uid: app.user?.uid,
                team: app.profile.team
            )

            let hasMissionComplete = missionSnap.isComplete
            let streakDays = app.dailyStreakCount
            let hasStreak = streakDays > 0

            let safeTop = geo.safeAreaInsets.top
            let headerTopPadding = max(0, safeTop - 2)
            let headerBandHeight: CGFloat = 54
            let headerTotalHeight = headerTopPadding + headerBandHeight

            ZStack {
                SpaceBackground(motionMode: .staticPremium)
                    .ignoresSafeArea()

                Color.black
                    .ignoresSafeArea()
                    .opacity(0.001)

                AmbientHaze()
                    .opacity(0.045)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        TopCommandChrome(topPadding: headerTopPadding)

                        HeaderBarV2(
                            title: "arena.header.title".localized,
                            subtitle: proEnabled ? "arena.header.pro".localized : "arena.header.free".localized,
                            onSettings: {
                                SpatialAudioHooks.tap()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    appRef.setRoute(.settings)
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
                            HeroCard(
                                isPro: proEnabled,
                                missionComplete: hasMissionComplete,
                                streakDays: streakDays,
                                onPrimary: {
                                    SpatialAudioManager.shared.play(.uiTap)
                                    appRef.startDailyMissionRun()
                                },
                                onSecondary: {
                                    SpatialAudioManager.shared.play(.uiTap)

                                    let cleaned = trainingTopicInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let topic = cleaned.isEmpty ? "General Knowledge" : cleaned

                                    guard proEnabled else {
                                        HapticManager.instance.errorJolt()
                                        appRef.setRoute(.proPaywall)
                                        return
                                    }

                                    appRef.beginTrainingArenaRun(topic: topic)
                                }
                            )
                            .premiumStroke(phase: 0.35, isOn: false)

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) {
                                    StatusChip(
                                        icon: "flame.fill",
                                        label: hasStreak
                                            ? "arena.status.day_streak".localized(streakDays)
                                            : "arena.status.no_streak".localized,
                                        style: hasStreak ? .warm : .neutral,
                                        pulsing: hasStreak
                                    )

                                    StatusChip(
                                        icon: hasMissionComplete ? "checkmark.seal.fill" : "target",
                                        label: hasMissionComplete
                                            ? "arena.status.mission_complete".localized
                                            : "arena.status.mission_ready".localized,
                                        style: hasMissionComplete ? .success : .neutral,
                                        pulsing: !hasMissionComplete
                                    )
                                }

                                VStack(spacing: 10) {
                                    StatusChip(
                                        icon: "flame.fill",
                                        label: hasStreak
                                            ? "arena.status.day_streak".localized(streakDays)
                                            : "arena.status.no_streak".localized,
                                        style: hasStreak ? .warm : .neutral,
                                        pulsing: hasStreak
                                    )

                                    StatusChip(
                                        icon: hasMissionComplete ? "checkmark.seal.fill" : "target",
                                        label: hasMissionComplete
                                            ? "arena.status.mission_complete".localized
                                            : "arena.status.mission_ready".localized,
                                        style: hasMissionComplete ? .success : .neutral,
                                        pulsing: !hasMissionComplete
                                    )
                                }
                            }
                            .padding(.top, 2)

                            TrainingCardV2(
                                isPro: proEnabled,
                                gateText: gateText,
                                isLocked: !proEnabled,
                                trainingTopic: $trainingTopicInput,
                                onStart: {
                                    SpatialAudioManager.shared.play(.uiTap)

                                    let cleaned = trainingTopicInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let topic = cleaned.isEmpty ? "General Knowledge" : cleaned

                                    guard proEnabled else {
                                        HapticManager.instance.errorJolt()
                                        appRef.setRoute(.proPaywall)
                                        return
                                    }

                                    appRef.beginTrainingArenaRun(topic: topic)
                                }
                            )

                            BattleEntryCardV2(
                                canOpenGlobalBattle: globalBattleIsUnlocked,
                                onOpenGlobalBattle: {
                                    SpatialAudioManager.shared.play(.uiTap)
                                    HapticManager.instance.impact(.light)

                                    let didHandle = appRef.openGlobalBattleIfEnabled()

                                    guard didHandle else {
                                        HapticManager.instance.errorJolt()

                                        #if DEBUG
                                        print("🌍 [ArenaGlobalBattleTap] blocked: didHandle=false, routeAfterTap=\(appRef.route)")
                                        #endif

                                        return
                                    }

                                    #if DEBUG
                                    print("🌍 [ArenaGlobalBattleTap] didHandle=\(didHandle), routeAfterTap=\(appRef.route)")
                                    #endif
                                }
                            )

                            CommandCardV2(
                                onMissions: {
                                    SpatialAudioManager.shared.play(.uiTap)
                                    appRef.startDailyMissionRun()
                                },
                                onResults: {
                                    SpatialAudioManager.shared.play(.uiTap)

                                    if appRef.openResults() == false {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            appRef.setRoute(.leaderboard)
                                        }
                                    }
                                }
                            )

                            WinnerSignalCard(
                                onOpenLeaderboard: {
                                    SpatialAudioManager.shared.play(.uiTap)
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        appRef.setRoute(.leaderboard)
                                    }
                                }
                            )
                            .environmentObject(appRef)
                            .premiumStroke(phase: 0.35, isOn: false)

                            if appRef.latestAIPulse != nil || appRef.latestCommunityPulse != nil {
                                CommunityPulseCard(
                                    latestAI: appRef.latestAIPulse,
                                    latestCommunity: appRef.latestCommunityPulse,
                                    hasUnread: appRef.hasUnreadCommunityPulse,
                                    onOpen: {
                                        SpatialAudioManager.shared.play(.uiTap)
                                        HapticManager.instance.impact(.light)
                                        appRef.markCommunityPulseRead()
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            appRef.setRoute(.community)
                                        }
                                    }
                                )
                                .premiumStroke(phase: 0.35, isOn: false)
                            }

                            if let run = appRef.lastRun {
                                LastRunCard(run: run) {
                                    SpatialAudioManager.shared.play(.uiTap)

                                    if appRef.openResults() == false {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            appRef.setRoute(.leaderboard)
                                        }
                                    }
                                }
                                .premiumStroke(phase: 0.35, isOn: false)
                            }

                            Spacer(minLength: 18)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 0)
                        .padding(.bottom, 28)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }

                if showReentryMoment {
                    HQRewardPulseOverlay(xp: reentryXP, tick: reentryTick)
                        .transition(.opacity.combined(with: .scale(scale: 1.01)))
                        .zIndex(999)
                        .allowsHitTesting(true)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .alert("arena.alert.no_results.title".localized, isPresented: $showNoResultsAlert) {
                Button("common.ok".localized, role: .cancel) { }
            } message: {
                Text("arena.alert.no_results.body".localized)
            }
            .onAppear {
                let cleanedName = app.profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedName = cleanedName.uppercased()

                if !cleanedName.isEmpty && normalizedName != "NEW PILOT" {
                    UserDefaults.standard.set(true, forKey: "tg.onboarding.isComplete")
                    UserDefaults.standard.set(cleanedName, forKey: "tg.user.codename")
                }

                SpatialAudioManager.shared.transition(to: .hq, force: true)
                enforceLobbyBGM(for: app.route)
                triggerHQReentryIfNeeded()
            }
            .onChange(of: app.route) { _, newRoute in
                enforceLobbyBGM(for: newRoute)
                if newRoute == .hq {
                    triggerHQReentryIfNeeded()
                }
            }
            .onChange(of: app.rewards.lastClaimKey) { _, _ in
                if app.route == .hq {
                    triggerHQReentryIfNeeded()
                }
            }
        }
    }

    private func enforceLobbyBGM(for route: AppState.Route) {
        let shouldKeepLobbyAudioAvailable: Bool = {
            switch route {
            case .hq, .settings, .leaderboard:
                return true
            default:
                return false
            }
        }()

        if shouldKeepLobbyAudioAvailable {
            SpatialAudioManager.shared.refreshAudioState()
        } else {
            SpatialAudioManager.shared.stopBGM()
        }
    }

    private func triggerHQReentryIfNeeded() {
        let key = app.rewards.lastClaimKey
        guard !key.isEmpty else { return }
        guard key != lastSeenClaimKey else { return }

        lastSeenClaimKey = key

        if let t = app.rewards.lastClaimedAt,
           Date().timeIntervalSince(t) > 120 {
            return
        }

        reentryXP = max(0, app.rewards.lastClaimedXP)
        reentryTick += 1

        if reentryXP > 0 {
            SpatialAudioHooks.victory()
        } else {
            SpatialAudioManager.shared.play(.lockIn)
        }

        HapticManager.instance.impact(.light)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            showReentryMoment = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.15) {
            withAnimation(.easeOut(duration: 0.24)) {
                showReentryMoment = false
            }
        }
    }
}

// MARK: - Private Support Views

private struct TopCommandChrome: View {
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

private struct HQRewardPulseOverlay: View {
    let xp: Int
    let tick: Int

    @State private var glow: Bool = false
    @State private var scale: CGFloat = 0.94
    @State private var textOpacity: Double = 0.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.orange.opacity(0.22),
                    Color.orange.opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(glow ? 0.22 : 0.10))
                        .frame(width: glow ? 132 : 104, height: glow ? 132 : 104)
                        .blur(radius: glow ? 18 : 10)

                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 106, height: 106)

                    Image(systemName: "sparkles")
                        .font(DS.Typography.font(30, weight: .black, design: .default, cappedAt: 34))
                        .foregroundColor(.orange.opacity(0.96))
                }

                Text(xp > 0 ? "arena.reward.xp".localized(xp) : "arena.reward.claimed".localized)
                    .font(DS.Typography.font(34, weight: .black, design: .rounded, cappedAt: 42))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.78)

                Text("arena.reward.vault_updated".localized)
                    .font(DS.Typography.font(13, weight: .semibold, design: .rounded, cappedAt: 17))
                    .foregroundColor(.white.opacity(0.66))
            }
            .padding(.horizontal, 24)
            .scaleEffect(scale)
            .opacity(textOpacity)
        }
        .onAppear { playIntro() }
        .onChange(of: tick) { _, _ in
            playIntro()
        }
    }

    private func playIntro() {
        glow = false
        scale = 0.94
        textOpacity = 0.0

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            scale = 1.0
            textOpacity = 1.0
        }

        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            glow = true
        }
    }
}

private struct WinnerSignalCard: View {
    @EnvironmentObject private var app: AppState
    let onOpenLeaderboard: () -> Void

    @State private var leaderName: String = "—"
    @State private var leaderXP: Int = 0
    @State private var lastLeaderNameKey: String = ""
    @State private var lastLeaderXP: Int = 0
    @State private var banner: Banner = .syncing
    @State private var pulse: Bool = false
    @State private var flareTick: Int = 0

    private enum Banner: Equatable {
        case syncing, leaderChanged, newHighScore, stable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("arena.winner.section".localized)

            Button(action: onOpenLeaderboard) {
                ZStack {
                    cardBackground
                    cardGlow

                    HStack(spacing: 12) {
                        crownCluster
                        textCluster
                        Spacer(minLength: 10)
                        statsCluster
                        chevron
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 12)
                }
                .overlay(cardBorder)
            }
            .buttonStyle(TGPressScaleStyle())
        }
        .tacticalPanel()
        .onAppear { applyTopPlayer(app.topPlayers.first) }
        .onReceive(app.$topPlayers) { players in applyTopPlayer(players.first) }
        .onChange(of: banner) { _, newValue in
            guard newValue == .leaderChanged || newValue == .newHighScore else { return }

            HapticManager.instance.impact(.light)
            SpatialAudioManager.shared.play(.victory)
            flareTick += 1

            guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
                pulse = false
                return
            }

            withAnimation(.easeInOut(duration: 0.22)) {
                pulse = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.35)) {
                    pulse = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if banner == .leaderChanged || banner == .newHighScore {
                    banner = .stable
                }
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.06))
    }

    private var cardGlow: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [Color.orange.opacity(glowOpacity), Color.clear],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 220
                )
            )
            .opacity(0.90)
    }

    private var crownCluster: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(pulse ? 0.22 : 0.12), lineWidth: 1)
                )

            Image(systemName: "crown.fill")
                .font(DS.Typography.font(18, weight: .black, design: .default, cappedAt: 20))
                .foregroundColor(.orange.opacity(0.95))

            WinnerFlareRing(tick: flareTick)
                .frame(width: 58, height: 58)
                .allowsHitTesting(false)
        }
    }

    private var textCluster: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headlineText)
                .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(leaderName)
                .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(subheadText)
                .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.62))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private var statsCluster: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("\(leaderXP) XP")
                .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                .foregroundColor(.orange.opacity(0.95))

            Text("arena.winner.current_number_one".localized)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.70))
                .tracking(1.1)

            Text(badgeText)
                .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                .foregroundColor(.black)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(Capsule().fill(Color.white.opacity(0.92)))
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(.white.opacity(0.28))
            .padding(.leading, 2)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(pulse ? 0.20 : 0.10), lineWidth: 1)
    }

    private var glowOpacity: Double {
        banner == .leaderChanged || banner == .newHighScore ? 0.22 : 0.08
    }

    private var headlineText: String {
        switch banner {
        case .syncing: return "arena.winner.headline.syncing".localized
        case .leaderChanged: return "arena.winner.headline.leader_changed".localized
        case .newHighScore: return "arena.winner.headline.new_high_score".localized
        case .stable: return "arena.winner.headline.stable".localized
        }
    }

    private var subheadText: String {
        switch banner {
        case .syncing: return "arena.winner.subhead.syncing".localized
        case .leaderChanged: return "arena.winner.subhead.leader_changed".localized
        case .newHighScore: return "arena.winner.subhead.new_high_score".localized
        case .stable: return "arena.winner.subhead.stable".localized
        }
    }

    private var badgeText: String {
        switch banner {
        case .syncing: return "arena.winner.badge.syncing".localized
        case .leaderChanged: return "arena.winner.badge.leader_changed".localized
        case .newHighScore: return "arena.winner.badge.new_high_score".localized
        case .stable: return "arena.winner.badge.stable".localized
        }
    }

    private func applyTopPlayer(_ top: UserProfile?) {
        guard let top else {
            banner = .syncing
            leaderName = "—"
            leaderXP = 0
            return
        }

        let rawName = top.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = rawName.isEmpty ? "common.pilot".localized : rawName
        let nameKey = resolvedName.uppercased()
        let leaderChanged = (!lastLeaderNameKey.isEmpty && nameKey != lastLeaderNameKey)
        let xpIncreased = (nameKey == lastLeaderNameKey && top.xp > lastLeaderXP)

        leaderName = resolvedName
        leaderXP = top.xp
        lastLeaderNameKey = nameKey
        lastLeaderXP = top.xp

        banner = leaderChanged ? .leaderChanged : xpIncreased ? .newHighScore : .stable
    }
}

private struct CommunityPulseCard: View {
    let latestAI: AppState.CommunityPulseItem?
    let latestCommunity: AppState.CommunityPulseItem?
    let hasUnread: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                SectionTitle("arena.community.section".localized)

                if hasUnread {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }

                Spacer()

                Text(hasUnread ? "arena.community.new".localized : "arena.community.live".localized)
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(.black)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    if let ai = latestAI {
                        pulseRow(
                            icon: "sparkles",
                            iconTint: .orange.opacity(0.95),
                            label: "arena.community.ai_insight".localized,
                            title: ai.title
                        )
                    }

                    if let community = latestCommunity {
                        pulseRow(
                            icon: "person.2.fill",
                            iconTint: .white.opacity(0.88),
                            label: "arena.community.community".localized,
                            title: community.title
                        )
                    }
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
            .buttonStyle(TGPressScaleStyle())
        }
        .tacticalPanel()
    }

    @ViewBuilder
    private func pulseRow(icon: String, iconTint: Color, label: String, title: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconTint)
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.60))
                    .tracking(1.0)

                Text(title)
                    .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))
                    .foregroundColor(.white.opacity(0.94))
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.24))
                .padding(.top, 2)
        }
    }
}

private struct WinnerFlareRing: View {
    let tick: Int
    @State private var animate: Bool = false

    var body: some View {
        Circle()
            .stroke(Color.orange.opacity(animate ? 0.0 : 0.30), lineWidth: 2)
            .scaleEffect(animate ? 1.12 : 0.65)
            .opacity(animate ? 0.0 : 1.0)
            .onChange(of: tick) { _, _ in
                guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }

                animate = false

                withAnimation(.easeOut(duration: 0.45)) {
                    animate = true
                }
            }
    }
}

private struct HeaderBarV2: View {
    let title: String
    let subtitle: String
    let onSettings: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.2)

                Text(subtitle)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(1.1)
            }

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.white.opacity(0.92))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(TGPressScaleStyle())
        }
    }
}

private struct HeroCard: View {
    let isPro: Bool
    let missionComplete: Bool
    let streakDays: Int
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    @State private var shimmer: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: missionComplete ? "checkmark.seal.fill" : "target")
                        .foregroundColor(missionComplete ? .green : .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("arena.hero.daily_mission".localized)
                            .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                            .foregroundColor(.white.opacity(0.7))

                        Text(missionComplete ? "arena.hero.mission_complete".localized : "arena.hero.ready".localized)
                            .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                if isPro {
                    Text("common.pro".localized)
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.black)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(Color.white))
                }
            }

            Text(missionComplete ? "arena.hero.complete_body".localized : "arena.hero.ready_body".localized)
                .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.62))

            HStack(spacing: 10) {
                Button(action: onPrimary) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text(missionComplete ? "arena.hero.run_again".localized : "arena.hero.start_mission".localized)
                    }
                    .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                }
                .buttonStyle(TGPressScaleStyle())

                Button(action: onSecondary) {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .font(DS.Typography.font(12, weight: .black, design: .default, cappedAt: 14))

                        Text("arena.hero.train".localized)
                            .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .allowsTightening(true)
                    }
                    .foregroundColor(.white)
                    .frame(width: 128, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(TGPressScaleStyle())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private struct TrainingCardV2: View {
    let isPro: Bool
    let gateText: String
    let isLocked: Bool

    @Binding var trainingTopic: String
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("arena.training.title".localized)

            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    Text("arena.training.placeholder".localized)
                        .font(DS.Typography.font(15, weight: .bold, design: .rounded, cappedAt: 19))
                        .foregroundColor(.white.opacity(trainingTopic.isEmpty ? 0.36 : 0.12))
                        .padding(.horizontal, 12)

                    TextField("", text: $trainingTopic)
                        .font(DS.Typography.font(15, weight: .semibold, design: .rounded, cappedAt: 19))
                        .foregroundColor(.white)
                        .tint(.orange)
                        .padding(.vertical, 11)
                        .padding(.horizontal, 12)
                        .disabled(isLocked)
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))

                Button(action: onStart) {
                    Text(isLocked ? "common.pro".localized : "common.start".localized)
                        .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                        .foregroundColor(isLocked ? .white : .black)
                        .frame(width: 92, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isLocked ? Color.orange.opacity(0.34) : Color.white)
                        )
                }
                .buttonStyle(TGPressScaleStyle())
            }

            HStack {
                Text(isPro ? "arena.training.pro_unlocked".localized : "arena.training.free_today".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text(gateText)
                    .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                    .foregroundColor(.white)
            }
        }
        .tacticalPanel()
    }
}

private struct BattleEntryCardV2: View {
    let canOpenGlobalBattle: Bool
    let onOpenGlobalBattle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("arena.multiplayer.title".localized)

            HubRowV2(
                icon: "globe.americas.fill",
                iconTint: .orange,
                title: "arena.global_battle.title".localized,
                subtitle: canOpenGlobalBattle ? "arena.global_battle.open".localized : "arena.global_battle.locked".localized,
                action: onOpenGlobalBattle
            )
            .overlay(
                canOpenGlobalBattle ? nil :
                    Text("common.pro".localized)
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color.white))
                    .padding(10),
                alignment: .topTrailing
            )
        }
        .tacticalPanel()
    }
}

private struct CommandCardV2: View {
    let onMissions: () -> Void
    let onResults: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("arena.command.title".localized)

            HubRowV2(
                icon: "flag.checkered",
                iconTint: .white,
                title: "arena.command.missions".localized,
                subtitle: "arena.command.missions_subtitle".localized,
                action: onMissions
            )

            HubRowV2(
                icon: "trophy.fill",
                iconTint: .orange,
                title: "arena.command.results".localized,
                subtitle: "arena.command.results_subtitle".localized,
                action: onResults
            )
        }
        .tacticalPanel()
    }
}

private struct LastRunCard: View {
    let run: AppState.LastRun
    let onView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("arena.last_run.title".localized)

            Button(action: onView) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.white.opacity(0.85))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(run.topic)
                            .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                            .foregroundColor(.white)

                        Text("arena.last_run.summary".localized(run.finalXP, run.scoreCorrect))
                            .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 15))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Spacer()

                    Text("common.view".localized)
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.black)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(TGPressScaleStyle())
        }
        .tacticalPanel()
    }
}

private struct SectionTitle: View {
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

private struct HubRowV2: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(iconTint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 15))
                        .foregroundColor(.white.opacity(0.55))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.28))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(TGPressScaleStyle())
    }
}

private struct StatusChip: View {
    enum Style {
        case warm
        case success
        case neutral
    }

    let icon: String
    let label: String
    let style: Style
    let pulsing: Bool

    private var tint: Color {
        switch style {
        case .warm: return .orange
        case .success: return .green
        case .neutral: return .white
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(tint)

            Text(label)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.74))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Capsule().fill(Color.white.opacity(0.045)))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(pulsing ? 0.14 : 0.10), lineWidth: 1)
        )
    }
}

private struct AmbientHaze: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.white.opacity(0.018),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct TGPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
