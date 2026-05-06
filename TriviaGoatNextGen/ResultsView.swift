//
//  ResultsView.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-03-04.
//

import SwiftUI
import UIKit

struct ResultsView: View {
    @EnvironmentObject private var app: AppState

    @State private var particles: [ResultsXPParticle] = []
    @State private var flashOpacity: Double = 0
    @State private var displayedXP: Int = 0
    @State private var stage: Int = 0
    @State private var didStartSequence: Bool = false
    @State private var didTapClaim: Bool = false
    @State private var sequenceWorkItems: [DispatchWorkItem] = []

    @State private var breakdownStep: Int = 0

    // MARK: - SSoT Snapshot

    private var run: AppState.LastRun? { app.lastRun }

    private var baseXP: Int { max(0, run?.baseXP ?? 0) }
    private var missionBonusXP: Int { max(0, run?.missionBonusXP ?? 0) }
    private var streakMulti: Double { run?.streakMultiplier ?? 1.0 }
    private var finalXP: Int { max(0, run?.finalXP ?? 0) }

    private var dailyStreakCount: Int { max(0, run?.dailyStreakCount ?? 0) }
    private var inferredPriorStreak: Int { max(0, dailyStreakCount - 1) }

    private var hasRun: Bool { run != nil }

    // MARK: - Streak Copy

    private var streakHeadline: String {
        let d = dailyStreakCount
        if d <= 0 { return "results.run_complete".localized }
        if d == 1 { return "results.streak.one_day".localized }
        return "results.streak.days".localized(d)
    }

    private var streakSubhead: String {
        let d = dailyStreakCount
        if d <= 0 { return "results.streak.empty".localized }
        if d == 1 { return "results.streak.day_one_locked".localized }
        return "results.streak.progress".localized(inferredPriorStreak, d)
    }

    // MARK: - Next Action

    private struct NextAction {
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color
        let primaryLabel: String
        let primaryRoute: AppState.Route
        let secondaryLabel: String
        let secondaryRoute: AppState.Route
    }

    private var nextAction: NextAction? {
        guard let r = run else { return nil }

        switch r.kind {
        case .dailyMission:
            return NextAction(
                title: "NEXT ACTION",
                subtitle: "Training keeps your streak momentum rolling.",
                icon: "flame.fill",
                tint: .orange.opacity(0.95),
                primaryLabel: "TRAINING ARENA",
                primaryRoute: .hq,
                secondaryLabel: "LEADERBOARD",
                secondaryRoute: .leaderboard
            )

        case .training:
            return NextAction(
                title: "NEXT ACTION",
                subtitle: "Hit Daily Mission for bonus XP today.",
                icon: "target",
                tint: DS.ColorToken.accent.opacity(0.95),
                primaryLabel: "DAILY MISSION",
                primaryRoute: .hq,
                secondaryLabel: "LEADERBOARD",
                secondaryRoute: .leaderboard
            )

        case .aiForge:
            return NextAction(
                title: "NEXT ACTION",
                subtitle: "Daily Mission gives bonus XP; Training builds streak.",
                icon: "bolt.fill",
                tint: .cyan.opacity(0.95),
                primaryLabel: "DAILY MISSION",
                primaryRoute: .hq,
                secondaryLabel: "TRAINING",
                secondaryRoute: .hq
            )

        case .unknown:
            return NextAction(
                title: "NEXT ACTION",
                subtitle: "Choose your next run.",
                icon: "arrow.right.circle.fill",
                tint: .white.opacity(0.85),
                primaryLabel: "ARENA",
                primaryRoute: .hq,
                secondaryLabel: "LEADERBOARD",
                secondaryRoute: .leaderboard
            )
        }
    }

    var body: some View {
        let claimDockVisible = stage == 3 && hasRun

        return ZStack {
            SpaceBackground()

            particleLayer

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 12)
                        .padding(.top, 8)

                    if stage >= 2 {
                        Group {
                            if hasRun {
                                resultsPanel(claimDockVisible: claimDockVisible)
                                    .padding(.horizontal, 16)
                            } else {
                                emptyResultsPanel
                                    .padding(.horizontal, 16)
                            }
                        }
                        .transition(.opacity.combined(with: .scale))
                    }

                    Color.clear
                        .frame(height: 176)

                    Spacer(minLength: 18)
                }
            }

            Color.white
                .ignoresSafeArea()
                .opacity(flashOpacity)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if stage == 3 {
                resultsBottomDock
            }
        }
        .onAppear {
            guard !didStartSequence else { return }
            didStartSequence = true

            if !hasRun {
                displayedXP = 0
                breakdownStep = 0
                flashOpacity = 0
                stage = 3
                return
            }

            runCinematicSequence()
        }
        .onDisappear {
            Task { @MainActor in
                SpatialAudioManager.shared.stopXPCountLoop()
            }
            cancelSequenceWork()
        }
    }

    // MARK: - Work Cancellation

    private func cancelSequenceWork() {
        sequenceWorkItems.forEach { $0.cancel() }
        sequenceWorkItems.removeAll()
    }

    private func scheduleSequenceWork(
        after delay: TimeInterval,
        _ action: @escaping () -> Void
    ) {
        let work = DispatchWorkItem(block: action)
        sequenceWorkItems.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Bottom Dock

    private var resultsBottomDock: some View {
        VStack(spacing: 0) {
            VStack {
                if hasRun {
                    claimButton
                        .disabled(didTapClaim)
                        .opacity(didTapClaim ? 0.78 : 1.0)
                } else {
                    backToArenaButton
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 10)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .padding(.top, 8)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Layers

    private var particleLayer: some View {
        GeometryReader { _ in
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .scaleEffect(p.scale)
                    .opacity(p.opacity)
                    .rotationEffect(p.rotation)
                    .position(x: p.x, y: p.y)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Main Panel

    private func resultsPanel(claimDockVisible: Bool) -> some View {
        VStack(spacing: 18) {
            streakHero

            microRewardsStrip
                .opacity(breakdownStep >= 4 ? 1.0 : 0.0)
                .offset(y: breakdownStep >= 4 ? 0 : 8)
                .animation(.spring(response: 0.30, dampingFraction: 0.85), value: breakdownStep)

            VStack(spacing: -8) {
                Text("\(displayedXP)")
                    .font(DS.Typography.font(96, weight: .black, design: .rounded, cappedAt: 112))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.60)
                    .lineLimit(1)

                Text("results.total_xp".localized)
                    .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 15))
                    .foregroundColor(DS.ColorToken.accent.opacity(0.95))
                    .tracking(4)
            }

            breakdownCard
                .opacity(breakdownStep > 0 ? 1.0 : 0.0)
                .offset(y: breakdownStep > 0 ? 0 : 10)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: breakdownStep)

            rankProgressCard
                .opacity(breakdownStep >= 4 ? 1.0 : 0.0)
                .offset(y: breakdownStep >= 4 ? 0 : 10)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: breakdownStep)


            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    if streakMulti > 1.0 {
                        ResultsStatBoxLocal(
                            title: "MULTI",
                            value: String(format: "%.2fx", streakMulti),
                            accent: .cyan
                        )
                    }

                    if missionBonusXP > 0 {
                        ResultsStatBoxLocal(
                            title: "BONUS",
                            value: "+\(missionBonusXP)",
                            accent: .orange
                        )
                    } else if streakMulti <= 1.0 {
                        ResultsStatBoxLocal(
                            title: "READY",
                            value: "NEXT RUN",
                            accent: DS.ColorToken.accent
                        )
                    }
                }

                VStack(spacing: 12) {
                    if streakMulti > 1.0 {
                        ResultsStatBoxLocal(
                            title: "MULTI",
                            value: String(format: "%.2fx", streakMulti),
                            accent: .cyan
                        )
                    }

                    if missionBonusXP > 0 {
                        ResultsStatBoxLocal(
                            title: "BONUS",
                            value: "+\(missionBonusXP)",
                            accent: .orange
                        )
                    } else if streakMulti <= 1.0 {
                        ResultsStatBoxLocal(
                            title: "READY",
                            value: "NEXT RUN",
                            accent: DS.ColorToken.accent
                        )
                    }
                }
            }
        }
        .tacticalPanel()
    }

    private var emptyResultsPanel: some View {
        VStack(spacing: 14) {
            Text("results.run_required".localized)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                .foregroundColor(DS.ColorToken.accent.opacity(0.9))
                .tracking(6)

            Text("results.no_results_yet".localized)
                .font(DS.Typography.font(32, weight: .black, design: .rounded, cappedAt: 40))
                .foregroundColor(.white)

            Text("results.empty.body".localized)
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)

            VStack(spacing: 10) {
                ResultsStatBoxLocal(title: "BASE XP", value: "—", accent: .white.opacity(0.6))
                ResultsStatBoxLocal(title: "FINAL XP", value: "—", accent: .white.opacity(0.6))
            }
        }
        .tacticalPanel()
    }

    // MARK: - Strip / Hero / Cards

    private var microRewardsStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                RewardChip(icon: "bolt.fill", text: "+\(finalXP) XP", tint: DS.ColorToken.accent)
                RewardChip(icon: "chart.line.uptrend.xyaxis", text: "RANK UPDATED", tint: .orange.opacity(0.95))
                RewardChip(
                    icon: "flame.fill",
                    text: dailyStreakCount > 0 ? "STREAK SAVED" : "MISSION READY",
                    tint: .orange.opacity(0.95)
                )
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    RewardChip(icon: "bolt.fill", text: "+\(finalXP) XP", tint: DS.ColorToken.accent)
                    RewardChip(icon: "chart.line.uptrend.xyaxis", text: "RANK UPDATED", tint: .orange.opacity(0.95))
                }

                RewardChip(
                    icon: "flame.fill",
                    text: dailyStreakCount > 0 ? "STREAK SAVED" : "MISSION READY",
                    tint: .orange.opacity(0.95)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, -4)
        .padding(.bottom, 2)
    }

    private var streakHero: some View {
        VStack(spacing: 8) {
            Text("results.protocol_complete".localized)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                .foregroundColor(DS.ColorToken.accent.opacity(0.9))
                .tracking(6)

            Text(streakHeadline)
                .font(DS.Typography.font(36, weight: .black, design: .rounded, cappedAt: 44))
                .foregroundColor(.white)
                .italic()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)
                .lineLimit(2)

            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 18))
                    .foregroundColor(.orange.opacity(0.95))

                Text(streakSubhead)
                    .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                    .foregroundColor(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var breakdownCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("results.breakdown".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(2)
                Spacer()
            }

            BreakdownRow(left: "BASE  XP", right: "\(baseXP)", isEmphasis: false)
                .opacity(breakdownStep >= 1 ? 1 : 0)
                .offset(y: breakdownStep >= 1 ? 0 : 8)
                .animation(.easeOut(duration: 0.22), value: breakdownStep)

            if missionBonusXP > 0 {
                BreakdownRow(left: "MISSION  BONUS", right: "+\(missionBonusXP)", isEmphasis: false)
                    .opacity(breakdownStep >= 2 ? 1 : 0)
                    .offset(y: breakdownStep >= 2 ? 0 : 8)
                    .animation(.easeOut(duration: 0.22), value: breakdownStep)
            }

            BreakdownRow(left: "STREAK  MULTI", right: "×\(String(format: "%.2f", streakMulti))", isEmphasis: false)
                .opacity(breakdownStep >= 3 ? 1 : 0)
                .offset(y: breakdownStep >= 3 ? 0 : 8)
                .animation(.easeOut(duration: 0.22), value: breakdownStep)

            Divider()
                .overlay(Color.white.opacity(0.10))

            BreakdownRow(left: "FINAL  XP", right: "\(finalXP)", isEmphasis: true)
                .opacity(breakdownStep >= 4 ? 1 : 0)
                .offset(y: breakdownStep >= 4 ? 0 : 8)
                .animation(.spring(response: 0.30, dampingFraction: 0.80), value: breakdownStep)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var rankProgressCard: some View {
        let xp = app.profile.xp
        let current = RankEngine.currentTier(for: xp)
        let next = RankEngine.nextTier(for: xp)
        let progress = RankEngine.progress(for: xp)
        let remaining = RankEngine.xpToNext(for: xp)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("results.rank_progress".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(2)

                Spacer()

                Text(current.name)
                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 14))
                    .foregroundColor(DS.ColorToken.accent.opacity(0.95))
            }

            ProgressView(value: progress)
                .tint(DS.ColorToken.accent)

            if let next {
                Text("\(remaining) XP to \(next.name)")
                    .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                    .foregroundColor(.white.opacity(0.70))
            } else {
                Text("results.max_tier".localized)
                    .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 15))
                    .foregroundColor(.white.opacity(0.70))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func nextActionCard(_ action: NextAction, showButtons: Bool) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(action.title)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(2)

                Spacer()

                Image(systemName: action.icon)
                    .font(DS.Typography.font(12, weight: .black, design: .default, cappedAt: 15))
                    .foregroundColor(action.tint)
            }

            Text(action.subtitle)
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                .foregroundColor(.white.opacity(0.70))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if showButtons {
                HStack(spacing: 10) {
                    Button {
                        HapticManager.instance.impact(.light)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            app.setRoute(action.primaryRoute)
                        }
                    } label: {
                        Text(action.primaryLabel)
                            .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 15))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(ChunkyButtonStyle(color: DS.ColorToken.accent))

                    Button {
                        HapticManager.instance.impact(.light)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            app.setRoute(action.secondaryRoute)
                        }
                    } label: {
                        Text(action.secondaryLabel)
                            .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 15))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Color.white.opacity(0.18)))
                }
            } else {
                Text("results.claim_to_continue".localized)
                    .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Buttons

    private var claimButton: some View {
        Button {
            guard !didTapClaim else { return }

            didTapClaim = true
            SpatialAudioHooks.rewardPresent()
            HapticManager.instance.impact(.light)
            app.claimGlory()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 18))
                Text("results.claim_glory".localized)
                    .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                    .tracking(0.4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
        .buttonStyle(ChunkyButtonStyle(color: DS.ColorToken.accent))
    }

    private var backToArenaButton: some View {
        Button {
            HapticManager.instance.impact(.light)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                app.setRoute(.hq)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.left")
                    .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 18))
                Text("results.back_to_arena".localized)
                    .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                    .tracking(0.4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
        .buttonStyle(ChunkyButtonStyle(color: Color.white.opacity(0.18)))
    }

    // MARK: - Sequence

    private func runCinematicSequence() {
        cancelSequenceWork()
        Task { @MainActor in
            SpatialAudioManager.shared.stopXPCountLoop()
        }

        let bounds = UIScreen.main.bounds
        let cx = bounds.width / 2
        let cy = bounds.height / 2

        displayedXP = 0
        stage = 0
        flashOpacity = 0
        breakdownStep = 0
        didTapClaim = false

        particles = (0..<30).map { _ in
            ResultsXPParticle(
                x: cx,
                y: cy,
                size: 8,
                color: DS.ColorToken.accent,
                scale: 1.0,
                opacity: 0.0,
                rotation: .degrees(Double.random(in: 0...360))
            )
        }

        withAnimation(.easeIn(duration: 0.7)) {
            stage = 1
            for i in particles.indices {
                particles[i].opacity = 1.0
            }
        }

        scheduleSequenceWork(after: 0.65) {
            HapticManager.instance.impact(.heavy)

            withAnimation(.easeInOut(duration: 0.10)) {
                flashOpacity = 1.0
                stage = 2
            }

            withAnimation(.easeOut(duration: 0.55).delay(0.08)) {
                flashOpacity = 0.0
            }

            for i in particles.indices {
                withAnimation(.easeOut(duration: 1.8)) {
                    particles[i].x += CGFloat.random(in: -300...300)
                    particles[i].y += CGFloat.random(in: -420...420)
                    particles[i].opacity = 0.0
                    particles[i].scale = 0.75
                }
            }

            scheduleSequenceWork(after: 0.12) {
                withAnimation { breakdownStep = 1 }
            }

            scheduleSequenceWork(after: 0.26) {
                withAnimation { breakdownStep = 2 }
            }

            scheduleSequenceWork(after: 0.40) {
                withAnimation { breakdownStep = 3 }
            }

            scheduleSequenceWork(after: 0.58) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    breakdownStep = 4
                }
            }

            let final = finalXP
            if final > 0 {
                Task { @MainActor in
                    SpatialAudioManager.shared.startXPCountLoop()
                }

                let step = max(10, final / 80)
                let ticks = Array(stride(from: 0, through: final, by: step))

                func finish() {
                    displayedXP = final
                    Task { @MainActor in
                        SpatialAudioManager.shared.stopXPCountLoop()
                    }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        stage = 3
                    }
                }

                func tick(_ i: Int) {
                    guard i < ticks.count else {
                        finish()
                        return
                    }

                    let work = DispatchWorkItem {
                        displayedXP = ticks[i]

                        if i % 4 == 0 || i == ticks.count - 1 {
                            HapticManager.instance.impact(.light)
                        }

                        tick(i + 1)
                    }

                    sequenceWorkItems.append(work)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: work)
                }

                tick(0)
            } else {
                displayedXP = 0
                Task { @MainActor in
                    SpatialAudioManager.shared.stopXPCountLoop()
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    stage = 3
                }
            }
        }
    }
}

// MARK: - Breakdown Row

private struct BreakdownRow: View {
    let left: String
    let right: String
    let isEmphasis: Bool

    var body: some View {
        HStack {
            Text(left)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                .foregroundColor(.white.opacity(isEmphasis ? 0.85 : 0.55))
                .tracking(1.5)

            Spacer()

            Text(right)
                .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 15))
                .foregroundColor(.white.opacity(isEmphasis ? 0.95 : 0.75))
        }
    }
}

// MARK: - Reward Chip

private struct RewardChip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(DS.Typography.font(11, weight: .black, design: .default, cappedAt: 14))
                .foregroundColor(tint.opacity(0.95))

            Text(text)
                .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.78))
                .tracking(1.0)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - Support Types

struct ResultsXPParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var scale: CGFloat
    var opacity: Double
    var rotation: Angle
}

private struct ResultsStatBoxLocal: View {
    let title: String
    let value: String
    var accent: Color = DS.ColorToken.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                .foregroundColor(accent.opacity(0.85))

            Text(value)
                .font(DS.Typography.font(18, weight: .black, design: .rounded, cappedAt: 22))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.80)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
