//
//  LeaderboardView.swift
//  TriviaGoatNextGen
//

import SwiftUI

/// ✅ Keep this name as the ONE true symbol referenced by routes.
/// IMPORTANT: There must be ONLY ONE `struct LeaderboardView` in the entire project.
struct LeaderboardView: View {
    var body: some View {
        LeaderboardScreen()
    }
}

private struct LeaderboardScreen: View {
    @EnvironmentObject var app: AppState

    @AppStorage("didSeeLeaderboardCoachV1") private var didSeeCoach: Bool = false

    @Namespace private var ladderNamespace

    @State private var showHowItWorks: Bool = false
    @State private var backPulse: Bool = false

    @State private var displayedEntries: [LeaderboardEntry] = []
    @State private var hasBoundInitialSnapshot: Bool = false
    @State private var hasPlayedRankMotionThisVisit: Bool = false

    @State private var motionBanner: RankMotionBanner? = nil
    @State private var bannerVisible: Bool = false
    @State private var glowUserID: String? = nil

    var body: some View {
        ZStack {
            SpaceBackground()

            GeometryReader { geo in
                let safeTop = geo.safeAreaInsets.top
                let safeBottom = geo.safeAreaInsets.bottom

                ZStack {
                    VStack(spacing: 10) {
                        header
                        helperStrip

                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 12) {
                                    if displayedEntries.isEmpty {
                                        emptyState
                                    } else {
                                        ForEach(Array(displayedEntries.enumerated()), id: \.element.stableID) { idx, entry in
                                            row(rank: idx + 1, entry: entry)
                                                .id(entry.stableID)
                                                .matchedGeometryEffect(id: entry.stableID, in: ladderNamespace)
                                                .overlay(alignment: .leading) {
                                                    if isCurrentUser(entry.profile) {
                                                        CurrentUserGlow(isActive: glowUserID == entry.stableID)
                                                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                                    }
                                                }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 2)
                                .padding(.bottom, 228)
                            }
                            .onAppear {
                                bindInitialBoardIfNeeded()
                                centerOnCurrentUser(proxy: proxy, animated: false)

                                app.refreshLeaderboard()

                                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                                    backPulse.toggle()
                                }
                            }
                            .onChange(of: app.topPlayers) { _, newValue in
                                let newEntries = makeEntries(from: newValue)

                                if !hasBoundInitialSnapshot {
                                    displayedEntries = newEntries
                                    hasBoundInitialSnapshot = true
                                    centerOnCurrentUser(proxy: proxy, animated: false)
                                    return
                                }

                                handleLeaderboardUpdate(newEntries, proxy: proxy)
                            }
                            .onDisappear {
                                app.cancelLeaderboardAutoRoute()
                            }
                        }
                    }
                    .padding(.top, max(8, safeTop + 2))

                    VStack(spacing: 10) {
                        Spacer()

                        if let banner = motionBanner, bannerVisible {
                            RankMotionBannerView(banner: banner)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .padding(.horizontal, 16)
                        } else {
                            footerActionModule
                                .padding(.horizontal, 16)
                        }

                        YourRankBar(
                            profile: app.profile,
                            computedRank: computedRank,
                            inTopList: isUserInTopList,
                            delta: deltaInt
                        ) {
                            app.cancelLeaderboardAutoRoute()
                            showHowItWorks = true
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, max(10, safeBottom + 2))
                    .background(
                        VStack {
                            Spacer()
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.42),
                                    Color.black.opacity(0.88)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 210)
                            .ignoresSafeArea(edges: .bottom)
                        }
                    )
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: bannerVisible)
                }
            }

            if !didSeeCoach {
                coachOverlay
                    .transition(.opacity)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    app.cancelLeaderboardAutoRoute()
                }
        )
        .onTapGesture {
            app.cancelLeaderboardAutoRoute()
        }
        .sheet(isPresented: $showHowItWorks) {
            howItWorksSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("leaderboard.title".localized)
                    .font(DS.Typography.font(14, weight: .black, design: .monospaced, cappedAt: 18))
                    .foregroundColor(.orange)
                    .tracking(2)

                Text("leaderboard.subtitle".localized)
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(.white.opacity(0.38))
                    .tracking(1.3)
            }

            Spacer()

            Button {
                app.cancelLeaderboardAutoRoute()
                HapticManager.instance.impact(.light)

                withAnimation(.spring()) {
                    app.setRoute(.hq)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(DS.Typography.font(12, weight: .black, design: .default, cappedAt: 14))
                        .foregroundColor(.white.opacity(0.90))

                    Text("leaderboard.back_to_hq".localized)
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.90))
                        .tracking(1.0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.orange.opacity(backPulse ? 0.35 : 0.0), lineWidth: 2)
                        .blur(radius: 0.4)
                        .scaleEffect(backPulse ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true), value: backPulse)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helper Strip

    private var helperStrip: some View {
        Button {
            app.cancelLeaderboardAutoRoute()
            HapticManager.instance.impact(.light)
            showHowItWorks = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 18))
                    .foregroundColor(.orange.opacity(0.95))

                VStack(alignment: .leading, spacing: 1) {
                    Text("leaderboard.info.title".localized)
                        .font(DS.Typography.font(11, weight: .black, design: .rounded, cappedAt: 14))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)

                    Text("leaderboard.info.body".localized)
                        .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(1.0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(DS.Typography.font(12, weight: .black, design: .default, cappedAt: 14))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - Bottom Dock

    private var footerActionModule: some View {
        VStack(spacing: 8) {
            if let target = nextTargetLine {
                HStack(spacing: 8) {
                    Image(systemName: target.icon)
                        .font(DS.Typography.font(11, weight: .black, design: .default, cappedAt: 13))
                        .foregroundColor(.orange.opacity(0.95))

                    Text(target.text)
                        .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                        .foregroundColor(.white.opacity(0.72))
                        .tracking(1.0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.74))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                        )
                )
            }

            HStack(spacing: 10) {
                Button {
                    app.cancelLeaderboardAutoRoute()
                    HapticManager.instance.impact(.light)

                    withAnimation(.spring()) {
                        if !app.openBattleDecisionIfAvailable() {
                            app.setRoute(.hq)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(DS.Typography.font(11, weight: .black, design: .default, cappedAt: 13))

                        Text("leaderboard.play_again".localized)
                            .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                            .tracking(1.0)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.95))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    app.cancelLeaderboardAutoRoute()
                    HapticManager.instance.impact(.light)

                    withAnimation(.spring()) {
                        app.setRoute(.hq)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "house.fill")
                            .font(DS.Typography.font(10, weight: .black, design: .default, cappedAt: 12))

                        Text("leaderboard.hq".localized)
                            .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                            .tracking(0.9)
                    }
                    .foregroundColor(.white.opacity(0.90))
                    .frame(width: 104, height: 44)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.orange)

            Text("leaderboard.syncing_pilots".localized)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.orange.opacity(0.8))
                .tracking(2)
        }
        .tacticalPanel()
    }

    // MARK: - Row

    private func row(rank: Int, entry: LeaderboardEntry) -> some View {
        let profile = entry.profile
        let isMe = isCurrentUser(profile)
        let isGlowing = glowUserID == entry.stableID

        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("#\(rank)")
                    .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))
                    .foregroundColor(.white.opacity(isMe ? 0.95 : 0.85))
                    .frame(width: 44, alignment: .leading)

                if let badge = badgeSymbol(for: rank) {
                    Image(systemName: badge.symbol)
                        .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 18))
                        .foregroundColor(badge.color)
                        .shadow(color: badge.color.opacity(0.20), radius: 10, x: 0, y: 8)
                        .accessibilityLabel(badge.label)
                }
            }

            PilotAvatar(profile: profile, teamColor: profile.team.color, rank: rank)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName.uppercased())
                    .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(profile.team.rawValue.uppercased())
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(1.1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(profile.xp) \("leaderboard.xp".localized)")
                    .font(DS.Typography.font(14, weight: .black, design: .monospaced, cappedAt: 18))
                    .foregroundColor(.orange)

                if isMe {
                    Text("common.you".localized)
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(1.4)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(isMe ? 0.74 : 0.60))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isGlowing
                            ? Color.orange.opacity(0.34)
                            : Color.white.opacity(isMe ? 0.22 : 0.12),
                            lineWidth: isMe ? 1.6 : 1.2
                        )
                )
        )
        .scaleEffect(isGlowing ? 1.015 : 1.0)
        .shadow(color: isGlowing ? Color.orange.opacity(0.12) : .clear, radius: 18, x: 0, y: 10)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isGlowing)
    }

    private func badgeSymbol(for rank: Int) -> (symbol: String, color: Color, label: String)? {
        switch rank {
        case 1: return ("crown.fill", .orange.opacity(0.95), "First place")
        case 2: return ("medal.fill", Color.white.opacity(0.88), "Second place")
        case 3: return ("medal.fill", Color(red: 0.82, green: 0.55, blue: 0.20).opacity(0.95), "Third place")
        default: return nil
        }
    }

    // MARK: - Coach Overlay

    private var coachOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text("leaderboard.landing.title".localized)
                        .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                        .foregroundColor(.orange.opacity(0.92))
                        .tracking(2)

                    Text("leaderboard.landing.body".localized + "\n" + "leaderboard.landing.subbody".localized)
                        .font(DS.Typography.font(18, weight: .black, design: .rounded, cappedAt: 24))
                        .foregroundColor(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left")
                            .font(DS.Typography.font(12, weight: .black, design: .default, cappedAt: 14))
                            .foregroundColor(.white.opacity(0.9))

                        Text("leaderboard.landing.hint".localized)
                            .font(DS.Typography.font(12, weight: .bold, design: .rounded, cappedAt: 16))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.top, 2)

                    Button {
                        app.cancelLeaderboardAutoRoute()
                        HapticManager.instance.impact(.light)

                        withAnimation(.easeOut(duration: 0.18)) {
                            didSeeCoach = true
                        }
                    } label: {
                        Text("leaderboard.landing.got_it".localized)
                            .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(ChunkyButtonStyle(color: .orange))
                }
                .tacticalPanel()
                .premiumStroke(isOn: true)
                .padding(.horizontal, 18)

                Spacer()
            }
        }
        .onTapGesture {
            app.cancelLeaderboardAutoRoute()
            didSeeCoach = true
        }
    }

    // MARK: - How It Works Sheet

    private var howItWorksSheet: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("leaderboard.how.title".localized)
                        .font(DS.Typography.font(14, weight: .black, design: .monospaced, cappedAt: 18))
                        .foregroundColor(.orange)
                        .tracking(2)

                    Spacer()

                    Button {
                        app.cancelLeaderboardAutoRoute()
                        showHowItWorks = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 16))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    bullet("leaderboard.how.bullet1".localized)
                    bullet("leaderboard.how.bullet2".localized)
                    bullet("leaderboard.how.bullet3".localized)
                    bullet("leaderboard.how.bullet4".localized)
                }
                .tacticalPanel()
                .premiumStroke(isOn: true)

                Button {
                    app.cancelLeaderboardAutoRoute()
                    HapticManager.instance.impact(.light)
                    showHowItWorks = false

                    withAnimation(.spring()) {
                        app.setRoute(.hq)
                    }
                } label: {
                    Text("leaderboard.go_to_hq".localized)
                        .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(ChunkyButtonStyle(color: .orange))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.orange.opacity(0.95))
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(s)
                .font(DS.Typography.font(14, weight: .bold, design: .rounded, cappedAt: 18))
                .foregroundColor(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Next Target

    private var nextTargetLine: (icon: String, text: String)? {
        let myXP = app.profile.xp

        if let idx = displayedEntries.firstIndex(where: { isCurrentUser($0.profile) }) {
            if idx > 0 {
                let above = displayedEntries[idx - 1].profile
                let need = max(0, above.xp - myXP + 1)

                if need > 0 {
                    return ("target", "leaderboard.next.pass".localized(need, above.displayName.uppercased()))
                } else {
                    return ("sparkles", "leaderboard.next.tied".localized)
                }
            } else {
                return ("crown.fill", "leaderboard.next.defend_crown".localized)
            }
        }

        if let last = displayedEntries.last?.profile {
            let need = max(0, last.xp - myXP + 1)
            if need > 0 {
                return ("arrow.up.right.circle.fill", "leaderboard.next.enter_top".localized(need, displayedEntries.count))
            }
        }

        return nil
    }

    // MARK: - Leaderboard Animation

    private func bindInitialBoardIfNeeded() {
        guard !hasBoundInitialSnapshot else { return }
        displayedEntries = makeEntries(from: app.topPlayers)
        hasBoundInitialSnapshot = true
    }

    private func handleLeaderboardUpdate(_ newEntries: [LeaderboardEntry], proxy: ScrollViewProxy) {
        guard !newEntries.isEmpty else { return }

        if displayedEntries.isEmpty {
            displayedEntries = newEntries
            centerOnCurrentUser(proxy: proxy, animated: false)
            return
        }

        let oldEntries = displayedEntries
        let oldUserRank = currentUserRank(in: oldEntries)
        let newUserRank = currentUserRank(in: newEntries)

        let boardChanged = oldEntries.map(\.stableID) != newEntries.map(\.stableID)
            || zip(oldEntries, newEntries).contains(where: { $0.profile.xp != $1.profile.xp })

        guard boardChanged else {
            displayedEntries = newEntries
            return
        }

        displayedEntries = oldEntries

        let shouldPlayMotion =
            !hasPlayedRankMotionThisVisit &&
            oldUserRank != nil &&
            newUserRank != nil &&
            oldUserRank != newUserRank

        if shouldPlayMotion {
            hasPlayedRankMotionThisVisit = true
            motionBanner = makeBanner(from: oldUserRank!, to: newUserRank!)
        } else {
            motionBanner = nil
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: shouldPlayMotion ? 320_000_000 : 80_000_000)

            withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) {
                displayedEntries = newEntries
                bannerVisible = shouldPlayMotion
            }

            if shouldPlayMotion {
                centerOnCurrentUser(proxy: proxy, animated: true)

                if let userID = currentUserEntryID(in: newEntries) {
                    glowUserID = userID
                }

                try? await Task.sleep(nanoseconds: 950_000_000)
                HapticManager.instance.impact(.light)

                try? await Task.sleep(nanoseconds: 1_700_000_000)
                withAnimation(.easeOut(duration: 0.22)) {
                    bannerVisible = false
                }

                try? await Task.sleep(nanoseconds: 800_000_000)
                motionBanner = nil
                glowUserID = nil
            } else {
                centerOnCurrentUser(proxy: proxy, animated: false)
            }
        }
    }

    private func centerOnCurrentUser(proxy: ScrollViewProxy, animated: Bool) {
        guard let id = currentUserEntryID(in: displayedEntries) else { return }

        if animated {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func makeEntries(from players: [UserProfile]) -> [LeaderboardEntry] {
        players.map { LeaderboardEntry(stableID: stableID(for: $0), profile: $0) }
    }

    private func stableID(for profile: UserProfile) -> String {
        let pid = (profile.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !pid.isEmpty { return "id:\(pid)" }

        let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "name:\(name)|team:\(profile.team.rawValue.lowercased())"
    }

    private func currentUserRank(in entries: [LeaderboardEntry]) -> Int? {
        guard let idx = entries.firstIndex(where: { isCurrentUser($0.profile) }) else { return nil }
        return idx + 1
    }

    private func currentUserEntryID(in entries: [LeaderboardEntry]) -> String? {
        entries.first(where: { isCurrentUser($0.profile) })?.stableID
    }

    private func makeBanner(from oldRank: Int, to newRank: Int) -> RankMotionBanner {
        if newRank < oldRank {
            return RankMotionBanner(
                icon: "arrow.up.right",
                title: "RANK UP",
                detail: "#\(oldRank) → #\(newRank)"
            )
        } else {
            return RankMotionBanner(
                icon: "arrow.down.right",
                title: "POSITION SHIFT",
                detail: "#\(oldRank) → #\(newRank)"
            )
        }
    }

    // MARK: - Current User matching

    private func isCurrentUser(_ p: UserProfile) -> Bool {
        if let pid = p.id, let myid = app.profile.id, !pid.isEmpty, !myid.isEmpty {
            return pid == myid
        }

        let a = p.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = app.profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (!a.isEmpty && a == b && p.team == app.profile.team)
    }

    private var isUserInTopList: Bool {
        displayedEntries.contains(where: { isCurrentUser($0.profile) })
    }

    private var computedRank: Int? {
        if let gr = app.profile.globalRank, gr > 0 { return gr }
        if let idx = displayedEntries.firstIndex(where: { isCurrentUser($0.profile) }) { return idx + 1 }
        return nil
    }

    private var deltaInt: Int? {
        extractDeltaInt(from: app.rankDelta)
    }

    private func extractDeltaInt(from rankDelta: Any?) -> Int? {
        guard let rankDelta else { return nil }

        let mirror = Mirror(reflecting: rankDelta)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first {
                return extractDeltaInt(from: child.value)
            }
            return nil
        }

        let m = Mirror(reflecting: rankDelta)

        func intField(_ name: String) -> Int? {
            m.children.first(where: { $0.label == name })?.value as? Int
        }

        if let d = intField("delta") ?? intField("change") ?? intField("value") {
            return d
        }

        let old = intField("oldRank") ?? intField("previousRank") ?? intField("fromRank") ?? intField("before")
        let new = intField("newRank") ?? intField("currentRank") ?? intField("toRank") ?? intField("after")
        if let old, let new { return old - new }

        return nil
    }
}
    
    // MARK: - Models
    
    private struct LeaderboardEntry: Equatable {
        let stableID: String
        let profile: UserProfile
    }
    
    private struct RankMotionBanner: Equatable {
        let icon: String
        let title: String
        let detail: String
    }
    
    // MARK: - Pinned “Your Rank” bar
    
    private struct YourRankBar: View {
        let profile: UserProfile
        let computedRank: Int?
        let inTopList: Bool
        let delta: Int?
        let onTap: () -> Void
        
        @State private var pulse: Bool = false
        
        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    PilotAvatar(profile: profile, teamColor: profile.team.color, rank: computedRank ?? 0)
                        .frame(width: 34, height: 34)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("leaderboard.your_rank".localized)
                            .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                            .foregroundColor(.white.opacity(0.68))
                            .tracking(1.5)
                        
                        HStack(spacing: 8) {
                            Text(rankText)
                                .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                                .foregroundColor(.white.opacity(0.94))
                            
                            if let d = delta, d != 0 {
                                RankDeltaChip(delta: d)
                            } else if !inTopList {
                                Text("leaderboard.outside_top_25".localized)
                                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                                    .foregroundColor(.white.opacity(0.62))
                                    .tracking(1.1)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 9)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(profile.xp) XP")
                            .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))
                            .foregroundColor(.orange.opacity(0.95))
                        
                        HStack(spacing: 7) {
                            Circle()
                                .fill(profile.team.color)
                                .frame(width: 9, height: 9)
                            
                            Text(profile.team.rawValue.uppercased())
                                .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                                .foregroundColor(.white.opacity(0.60))
                                .tracking(1.0)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.orange.opacity(pulse ? 0.28 : 0.16), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.48), radius: 18, x: 0, y: 14)
                        .shadow(color: .orange.opacity(0.10), radius: 14, x: 0, y: 10)
                )
            }
            .buttonStyle(.plain)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                    pulse.toggle()
                }
            }
        }
        
        private var rankText: String {
            if let r = computedRank { return "#\(r)" }
            return "—"
        }
    }
    
    private struct RankDeltaChip: View {
        let delta: Int
        
        var body: some View {
            let up = delta > 0
            let label = up ? "▲ \(delta)" : "▼ \(abs(delta))"
            
            return Text(label)
                .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                .foregroundColor(.black)
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(Capsule().fill(Color.white.opacity(0.92)))
        }
    }
    
    private struct RankMotionBannerView: View {
        let banner: RankMotionBanner
        
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: banner.icon)
                    .font(DS.Typography.font(12, weight: .black, design: .default, cappedAt: 14))
                    .foregroundColor(.orange.opacity(0.95))
                
                Text(banner.title)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.2)
                
                Text(banner.detail)
                    .font(DS.Typography.font(11, weight: .black, design: .rounded, cappedAt: 14))
                    .foregroundColor(.white.opacity(0.90))
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.84))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }
    
    private struct CurrentUserGlow: View {
        let isActive: Bool
        @State private var breathe: Bool = false
        
        var body: some View {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(isActive ? (breathe ? 0.24 : 0.14) : 0.10),
                            Color.clear
                        ],
                        center: .leading,
                        startRadius: 8,
                        endRadius: 220
                    )
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        breathe.toggle()
                    }
                }
        }
    }
    
    // MARK: - Avatar
    
    private struct PilotAvatar: View {
        let profile: UserProfile
        let teamColor: Color
        let rank: Int
        
        var body: some View {
            let ring = ringColor(for: rank)
            
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.black.opacity(0.70)
                            ],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 34
                        )
                    )
                
                if let url = avatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                            
                        case .empty:
                            ProgressView()
                                .tint(.orange)
                                .scaleEffect(0.7)
                            
                        case .failure:
                            fallbackAvatar
                            
                        @unknown default:
                            fallbackAvatar
                        }
                    }
                } else {
                    fallbackAvatar
                }
                
                Circle().stroke(teamColor.opacity(0.55), lineWidth: 2)
                Circle().stroke(ring.opacity(0.85), lineWidth: 1.4).padding(1.5)
                
                if rank == 1 {
                    Image(systemName: "crown.fill")
                        .font(DS.Typography.font(10, weight: .black, design: .default, cappedAt: 12))
                        .foregroundColor(.orange.opacity(0.95))
                        .offset(x: 12, y: -12)
                } else if rank == 2 || rank == 3 {
                    Image(systemName: "medal.fill")
                        .font(DS.Typography.font(10, weight: .black, design: .default, cappedAt: 12))
                        .foregroundColor(rank == 2 ? Color.white.opacity(0.88) : Color(red: 0.82, green: 0.55, blue: 0.20))
                        .offset(x: 12, y: -12)
                }
            }
            .clipShape(Circle())
            .accessibilityLabel(Text("Avatar \(profile.displayName)"))
        }
        
        private var avatarURL: URL? {
            let rawStyle = profile.avatarStyle.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawSeed = profile.avatarSeed.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let style = rawStyle.isEmpty ? "adventurer" : rawStyle
            let seed = rawSeed.isEmpty ? "TriviaGoatAlpha" : rawSeed
            
            let safeStyle = style.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? style
            let safeSeed = seed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? seed
            
            return URL(string: "https://api.dicebear.com/9.x/\(safeStyle)/png?seed=\(safeSeed)&size=128")
        }
        
        private var fallbackAvatar: some View {
            Text(initialsFromName(profile.displayName))
                .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 14))
                .foregroundColor(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)
        }
        
        private func initialsFromName(_ s: String) -> String {
            let parts = s.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if parts.count >= 2 { return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased() }
            return String(s.prefix(2)).uppercased()
        }
        
        private func ringColor(for rank: Int) -> Color {
            switch rank {
            case 1: return .orange.opacity(0.95)
            case 2: return .white.opacity(0.75)
            case 3: return Color(red: 0.82, green: 0.55, blue: 0.20).opacity(0.85)
            default: return .white.opacity(0.10)
            }
        }
    }

