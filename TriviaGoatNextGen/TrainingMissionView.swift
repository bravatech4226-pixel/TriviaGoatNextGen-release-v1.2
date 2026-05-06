//
//  TrainingMissionView.swift
//  TriviaGoatNextGen
//

import SwiftUI
import UIKit

struct TrainingMissionView: View {
    @EnvironmentObject private var app: AppState

    // Selection
    @State private var selectedIndex: Int? = nil

    // Latches
    @State private var didLock: Bool = false
    @State private var isAdvancing: Bool = false

    // Reveal phases
    enum RevealPhase: Equatable {
        case idle
        case suspense(choice: Int)
        case revealed(choice: Int)
    }
    @State private var phase: RevealPhase = .idle

    // Reveal de-dupe
    @State private var lastRevealKey: String = ""

    // Micro FX
    @State private var flashTick: Int = 0
    @State private var correctPulseTick: Int = 0
    @State private var wrongShakeTick: Int = 0

    // Ambient motion
    @State private var hazeDrift: Bool = false

    // Milestone / flame punch
    @State private var lastMilestoneTriggered: Int = 0
    @State private var flamePunchTick: Int = 0

    // Bottom dock
    @State private var lastWasCorrect: Bool? = nil
    @State private var coachTick: Int = 0

    // Premium praise overlay
    @State private var praise: PraiseMoment? = nil
    @State private var praiseTick: Int = 0

    // Safer async control
    @State private var revealTask: Task<Void, Never>? = nil

    struct PraiseMoment: Equatable {
        enum Tier: Equatable {
            case heat
            case lockedIn
            case unstoppable
            case legend
        }

        let text: String
        let tier: Tier
        let streak: Int
    }

    // Timing
    private let suspenseDelay: TimeInterval = 0.18
    private let revealHold: TimeInterval = 1.05

    private var hotRunToneOpacity: Double {
        app.streakCount >= 7 ? 0.040 : 0.0
    }
    
    private var isRewardMomentActive: Bool {
        praise != nil
    }

    var body: some View {
        ZStack {
            SpaceBackground()

            TrainingAmbientHaze(drift: hazeDrift)
                .opacity(0.20)
                .allowsHitTesting(false)

            Color.orange
                .ignoresSafeArea()
                .opacity(hotRunToneOpacity)
                .animation(.easeInOut(duration: 0.55), value: app.streakCount)

            VStack(spacing: 14) {
                topBar

                if let q = app.currentQuestion {
                    questionCard(q)
                    choicesCard(q)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 0)
            .allowsHitTesting(!isRewardMomentActive)
            .opacity(isRewardMomentActive ? 0.12 : 1.0)
            .blur(radius: isRewardMomentActive ? 2.0 : 0)
            .animation(.easeInOut(duration: 0.20), value: isRewardMomentActive)

            if let praise {
                TrainingPremiumPraiseOverlay(
                    moment: praise,
                    trigger: praiseTick
                )
                .allowsHitTesting(true)
                .transition(.opacity)
                .zIndex(50)
            }

            Color.white
                .ignoresSafeArea()
                .opacity(flashTick > 0 ? 0.05 : 0.0)
                .animation(.easeOut(duration: 0.18), value: flashTick)
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TrainingMomentumDock(
                streak: app.streakCount,
                score: app.trivia.score,
                currentIndex: app.trivia.currentIndex,
                total: app.trivia.pack.count,
                phase: phase,
                didLock: didLock,
                lastWasCorrect: lastWasCorrect,
                tick: coachTick
            )
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .allowsHitTesting(!isRewardMomentActive)
            .opacity(isRewardMomentActive ? 0.10 : 1.0)
            .blur(radius: isRewardMomentActive ? 2.0 : 0)
            .animation(.easeInOut(duration: 0.20), value: isRewardMomentActive)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.70),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        .onAppear {
            app.ensureTriviaRunLoaded()

            withAnimation(.easeInOut(duration: 8.5).repeatForever(autoreverses: true)) {
                hazeDrift.toggle()
            }
        }
        .onDisappear {
            cancelRevealTask()
        }
        .onChange(of: app.trivia.currentIndex) { _, _ in
            resetForNewQuestion()
        }
        .onChange(of: app.streakCount) { _, newValue in
            handleStreakChange(newValue)
        }
    }
}

// MARK: - UI

private extension TrainingMissionView {

    var topBar: some View {
        let displayTopic = trainingDisplayTopic(from: app.trivia.topic)

        return HStack(alignment: .center) {
            Button {
                cancelRevealTask()
                HapticManager.instance.impact(.light)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    app.setRoute(.hq)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(DS.Typography.font(18, weight: .black, design: .rounded, cappedAt: 22))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .pressScale()

            Spacer()

            VStack(spacing: 2) {
                Text("TRAINING ARENA")
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(2)

                Text(displayTopic.uppercased())
                    .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("SCORE \(app.trivia.score)")
                    .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 16))
                    .foregroundColor(.white.opacity(0.9))

                HStack(spacing: 8) {
                    Text("STREAK \(app.streakCount)")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.5))

                    TrainingLoudFlame(
                        streak: app.streakCount,
                        punch: flamePunchTick
                    )
                }

                TrainingMiniHeat(streak: app.streakCount)
                    .frame(width: 52, height: 6)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    func questionCard(_ q: TriviaQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("QUESTION \(app.trivia.currentIndex + 1)/\(max(1, app.trivia.pack.count))")
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(2)

                Spacer()
            }

            Text(q.prompt)
                .font(DS.Typography.font(20, weight: .black, design: .rounded, cappedAt: 27))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tacticalPanel()
        .premiumStroke(isOn: true)
    }

    func choicesCard(_ q: TriviaQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(q.choices.enumerated()), id: \.offset) { idx, title in
                TrainingChoiceRowView(
                    idx: idx,
                    title: title,
                    correctIndex: q.correctIndex,
                    selectedIndex: selectedIndex,
                    phase: phase,
                    correctPulseTick: correctPulseTick,
                    wrongShakeTick: wrongShakeTick
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canTapChoice else { return }
                    HapticManager.instance.impact(.light)
                    selectedIndex = idx
                }
            }

            Button {
                lockOrAdvance(question: q)
            } label: {
                Text(didLock ? "ADVANCE" : "LOCK IN")
                    .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(ChunkyButtonStyle(color: didLock ? .white.opacity(0.18) : .orange))
            .disabled(((selectedIndex == nil) && !didLock) || isAdvancing || isRewardMomentActive)
            .padding(.top, 8)
            .pressScale()
        }
        .tacticalPanel()
        .premiumStroke(isOn: true)
    }

    var canTapChoice: Bool {
        if isRewardMomentActive { return false }
        if isAdvancing { return false }
        if didLock { return false }
        if case .suspense = phase { return false }
        if case .revealed = phase { return false }
        return true
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Text("LOADING TRAINING…")
                .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 15))
                .foregroundColor(.white.opacity(0.5))
                .tracking(2)

            Button {
                cancelRevealTask()
                HapticManager.instance.impact(.light)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    app.setRoute(.hq)
                }
            } label: {
                Text("RETURN TO HQ")
                    .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                    .frame(width: 260, height: 56)
            }
            .buttonStyle(ChunkyButtonStyle(color: .orange))
            .pressScale()
        }
        .tacticalPanel()
        .premiumStroke(isOn: true)
        .padding(.top, 40)
    }
}

// MARK: - Streak Moments

private extension TrainingMissionView {

    func handleStreakChange(_ newValue: Int) {
        let milestones: Set<Int> = [3, 5, 7, 10]
        guard milestones.contains(newValue) else { return }
        guard newValue != lastMilestoneTriggered else { return }

        lastMilestoneTriggered = newValue
        flamePunchTick += 1

        HapticManager.instance.successPulse()
        SpatialAudioManager.shared.play(.correct)

        if let moment = praiseMoment(for: newValue) {
            presentPraise(moment)
        }
    }

    private func praiseMoment(for streak: Int) -> PraiseMoment? {
        switch streak {
        case 3:
            return PraiseMoment(text: "ON FIRE", tier: .heat, streak: streak)
        case 5:
            return PraiseMoment(text: "LOCKED IN", tier: .lockedIn, streak: streak)
        case 7:
            return PraiseMoment(text: "UNSTOPPABLE", tier: .unstoppable, streak: streak)
        case 10:
            return PraiseMoment(text: "LEGEND RUN", tier: .legend, streak: streak)
        default:
            return nil
        }
    }

    private func presentPraise(_ moment: PraiseMoment) {
        praise = moment
        praiseTick += 1

        let expectedTick = praiseTick

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if praiseTick == expectedTick, praise?.streak == moment.streak {
                praise = nil
            }
        }
    }
}

// MARK: - Actions

private extension TrainingMissionView {

    func lockOrAdvance(question q: TriviaQuestion) {
        guard !isAdvancing else { return }
        guard !isRewardMomentActive else { return }

        if didLock {
            advance()
            return
        }

        guard let idx = selectedIndex else { return }

        didLock = true
        isAdvancing = true

        SpatialAudioManager.shared.play(.lockIn)
        HapticManager.instance.rigidClick()
        flashTick += 1

        phase = .suspense(choice: idx)

        app.submitAnswer(index: idx)

        cancelRevealTask()
        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(suspenseDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard didLock else { return }
            guard app.currentQuestion?.id == q.id else { return }

            fireRevealFX(question: q, picked: idx)
            phase = .revealed(choice: idx)

            try? await Task.sleep(nanoseconds: UInt64(revealHold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard didLock else { return }
            guard app.currentQuestion?.id == q.id else { return }

            while praise != nil && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000)
            }

            guard !Task.isCancelled else { return }
            guard didLock else { return }
            guard app.currentQuestion?.id == q.id else { return }

            advance()
        }
    }

    func advance() {
        guard praise == nil else { return }

        cancelRevealTask()

        HapticManager.instance.impact(.medium)

        isAdvancing = false
        didLock = false
        selectedIndex = nil
        phase = .idle

        app.advanceTrivia()
    }

    func fireRevealFX(question q: TriviaQuestion, picked: Int) {
        let key = "\(app.trivia.currentIndex)-\(q.correctIndex)-\(picked)"
        guard key != lastRevealKey else { return }
        lastRevealKey = key

        let wasCorrect = (picked == q.correctIndex)
        lastWasCorrect = wasCorrect
        coachTick += 1

        if wasCorrect {
            SpatialAudioManager.shared.play(.correct)
            HapticManager.instance.successPulse()
            correctPulseTick += 1
        } else {
            SpatialAudioManager.shared.play(.wrong)
            HapticManager.instance.errorJolt()
            wrongShakeTick += 1
        }
    }

    func resetForNewQuestion() {
        cancelRevealTask()

        praise = nil

        selectedIndex = nil
        didLock = false
        isAdvancing = false
        phase = .idle
        lastRevealKey = ""
        lastWasCorrect = nil
        flashTick = 0
        correctPulseTick = 0
        wrongShakeTick = 0
        coachTick += 1
    }

    func cancelRevealTask() {
        revealTask?.cancel()
        revealTask = nil
    }
}

// MARK: - Helpers

private extension TrainingMissionView {
    func trainingDisplayTopic(from raw: String?) -> String {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "TRAINING" }

        var cleaned = s
        cleaned = cleaned
            .replacingOccurrences(of: "TRAINING ARENA:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned
            .replacingOccurrences(of: "TRAINING:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "TRAINING" : cleaned
    }
}

// MARK: - Premium Praise Overlay

private struct TrainingPremiumPraiseOverlay: View {
    let moment: TrainingMissionView.PraiseMoment
    let trigger: Int

    @State private var textScale: CGFloat = 0.88
    @State private var textOpacity: Double = 0.0
    @State private var glowOpacity: Double = 0.0
    @State private var ringScale: CGFloat = 0.84
    @State private var ringOpacity: Double = 0.0
    @State private var fracture: Bool = false
    @State private var darkFade: Double = 0.0

    var body: some View {
        GeometryReader { geo in
            let centerY = geo.size.height * 0.34

            ZStack {
                RadialGradient(
                    colors: [
                        haloColor.opacity(glowOpacity),
                        haloColor.opacity(glowOpacity * 0.32),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 8,
                    endRadius: 190
                )
                .frame(width: 360, height: 360)
                .position(x: geo.size.width / 2, y: centerY)

                Circle()
                    .stroke(Color.white.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 250, height: 250)
                    .scaleEffect(ringScale)
                    .blur(radius: 1.0)
                    .position(x: geo.size.width / 2, y: centerY)

                if fracture {
                    TrainingFractureShardField(tier: moment.tier)
                        .frame(width: 320, height: 240)
                        .position(x: geo.size.width / 2, y: centerY + 4)
                }

                VStack(spacing: 8) {
                    if moment.streak >= 5 {
                        TrainingGoatMarkBadge(tier: moment.tier)
                    }

                    Text(moment.text)
                        .font(DS.Typography.font(fontSize, weight: .black, design: .rounded, cappedAt: fontSize + 6))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.98),
                                    haloColor.opacity(0.92)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: haloColor.opacity(0.38), radius: 18, x: 0, y: 8)
                        .tracking(1.0)
                }
                .scaleEffect(textScale)
                .opacity(textOpacity)
                .position(x: geo.size.width / 2, y: centerY)

                Color.black
                    .opacity(darkFade)
                    .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .onAppear { runSequence() }
        .onChange(of: trigger) { _, _ in
            runSequence()
        }
    }

    private var haloColor: Color {
        switch moment.tier {
        case .heat: return .orange
        case .lockedIn: return .orange
        case .unstoppable: return .white
        case .legend: return .orange
        }
    }

    private var fontSize: CGFloat {
        switch moment.tier {
        case .heat: return 34
        case .lockedIn: return 38
        case .unstoppable: return 40
        case .legend: return 42
        }
    }

    private func runSequence() {
        textScale = 0.88
        textOpacity = 0.0
        glowOpacity = 0.0
        ringScale = 0.84
        ringOpacity = 0.0
        fracture = false
        darkFade = 0.0

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            textScale = 1.0
            textOpacity = 1.0
            glowOpacity = 0.30
            ringScale = 1.0
            ringOpacity = 0.20
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 0.18)) {
                fracture = true
                glowOpacity = 0.18
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            withAnimation(.easeOut(duration: 0.42)) {
                textOpacity = 0.0
                textScale = 1.04
                ringOpacity = 0.0
                ringScale = 1.12
                darkFade = 0.06
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation(.easeOut(duration: 0.18)) {
                fracture = false
                darkFade = 0.0
            }
        }
    }
}

private struct TrainingGoatMarkBadge: View {
    let tier: TrainingMissionView.PraiseMoment.Tier

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 58, height: 58)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            Image(systemName: badgeSymbol)
                .font(DS.Typography.font(22, weight: .black, design: .default, cappedAt: 26))
                .foregroundColor(badgeTint)
        }
    }

    private var badgeSymbol: String {
        switch tier {
        case .heat: return "flame.fill"
        case .lockedIn: return "bolt.fill"
        case .unstoppable: return "shield.fill"
        case .legend: return "crown.fill"
        }
    }

    private var badgeTint: Color {
        switch tier {
        case .heat, .lockedIn, .legend:
            return .orange.opacity(0.96)
        case .unstoppable:
            return .white.opacity(0.94)
        }
    }
}

private struct TrainingFractureShardField: View {
    let tier: TrainingMissionView.PraiseMoment.Tier
    @State private var scatter: Bool = false
    @State private var fade: Bool = false

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                TrainingFractureShard(
                    index: i,
                    tier: tier,
                    scatter: scatter,
                    fade: fade
                )
            }
        }
        .onAppear {
            scatter = false
            fade = false

            withAnimation(.easeOut(duration: 0.34)) {
                scatter = true
            }

            withAnimation(.easeOut(duration: 0.30).delay(0.08)) {
                fade = true
            }
        }
    }
}

private struct TrainingFractureShard: View {
    let index: Int
    let tier: TrainingMissionView.PraiseMoment.Tier
    let scatter: Bool
    let fade: Bool

    private var xOffsets: [CGFloat] { [-120, -98, -76, -54, -32, -12, 16, 34, 56, 78, 98, 118, -44, 46] }
    private var yOffsets: [CGFloat] { [-42, -56, -24, -70, -38, -16, -18, -34, -62, -28, -48, -22, 10, 8] }
    private var widths: [CGFloat] { [14, 18, 12, 16, 10, 12, 15, 11, 14, 12, 18, 10, 16, 14] }
    private var heights: [CGFloat] { [5, 6, 4, 5, 4, 4, 5, 4, 5, 4, 6, 4, 5, 5] }
    private var angles: [Double] { [-28, -16, -12, -34, -8, 12, 18, 22, 28, 34, 16, 10, -18, 14] }

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(shardColor.opacity(fade ? 0.0 : 0.92))
            .frame(width: widths[index], height: heights[index])
            .rotationEffect(.degrees(angles[index]))
            .offset(
                x: scatter ? xOffsets[index] : 0,
                y: scatter ? yOffsets[index] : 0
            )
            .scaleEffect(scatter ? 0.76 : 1.0)
            .blur(radius: fade ? 1.2 : 0.0)
    }

    private var shardColor: Color {
        switch tier {
        case .heat, .lockedIn, .legend:
            return .orange
        case .unstoppable:
            return .white
        }
    }
}

// MARK: - Momentum Dock

private struct TrainingMomentumDock: View {
    let streak: Int
    let score: Int
    let currentIndex: Int
    let total: Int
    let phase: TrainingMissionView.RevealPhase
    let didLock: Bool
    let lastWasCorrect: Bool?
    let tick: Int

    @State private var pulse: Bool = false
    @State private var flash: Bool = false

    var body: some View {
        let t = max(1, total)
        let q = min(max(1, currentIndex + 1), t)
        let progress = Double(q) / Double(t)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))
                    .foregroundColor(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 10) {
                    Text("STREAK \(streak)")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(1.2)

                    Text("•")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.22))

                    Text("SCORE \(score)")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(1.2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text("Q \(q)/\(t)")
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(1.2)

                XPVolumetricBar(progress: progress)
                    .frame(width: 120, height: 6)
                    .opacity(0.95)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.orange.opacity(pulse ? 0.26 : 0.14), lineWidth: 1.4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(flash ? 0.08 : 0.0))
                )
                .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 14)
                .shadow(color: .orange.opacity(0.10), radius: 18, x: 0, y: 12)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
        .onChange(of: tick) { _, _ in
            flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                flash = false
            }
        }
    }

    private var headline: String {
        if didLock {
            switch phase {
            case .suspense:
                return "LOCKED. HOLDING…"
            case .revealed:
                if lastWasCorrect == true { return "CONFIRMED. NICE." }
                if lastWasCorrect == false { return "MISSED. RESET FAST." }
                return "CONFIRMED."
            case .idle:
                break
            }
        }

        if streak >= 10 { return "LEGEND TRAINING RUN." }
        if streak >= 7  { return "LOCKED IN. KEEP THE HEAT." }
        if streak >= 5  { return "FIVE-STACK. NICE CONTROL." }
        if streak >= 3  { return "ON FIRE. STAY CLEAN." }

        if lastWasCorrect == false { return "SHAKE IT OFF. NEXT ONE." }
        if lastWasCorrect == true  { return "GOOD. BUILD IT UP." }

        return "TRAINING MODE. ONE CLEAN ANSWER."
    }
}

// MARK: - Choice Row

private struct TrainingChoiceRowView: View {
    let idx: Int
    let title: String
    let correctIndex: Int
    let selectedIndex: Int?
    let phase: TrainingMissionView.RevealPhase
    let correctPulseTick: Int
    let wrongShakeTick: Int

    private var lockedChoice: Int? {
        switch phase {
        case .idle: return nil
        case .suspense(let c): return c
        case .revealed(let c): return c
        }
    }

    private var isLockedPick: Bool { lockedChoice == idx }
    private var isSelected: Bool { selectedIndex == idx }

    private var isReveal: Bool {
        if case .revealed = phase { return true }
        return false
    }

    private var isCorrect: Bool { isReveal && idx == correctIndex }
    private var isWrongSelected: Bool { isReveal && isLockedPick && idx != correctIndex }

    var body: some View {
        HStack(spacing: 12) {
            Text(letter(for: idx))
                .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 15))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 22, alignment: .leading)

            Text(title)
                .font(DS.Typography.font(15, weight: .bold, design: .rounded, cappedAt: 19))
                .foregroundColor(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if isReveal && isCorrect {
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.Typography.font(18, weight: .bold, design: .default, cappedAt: 21))
                    .foregroundColor(.green.opacity(0.9))
            } else if isReveal && isWrongSelected {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Typography.font(18, weight: .bold, design: .default, cappedAt: 21))
                    .foregroundColor(.red.opacity(0.9))
            } else if isSelected {
                Image(systemName: "circle.fill")
                    .font(DS.Typography.font(10, weight: .black, design: .default, cappedAt: 12))
                    .foregroundColor(.orange.opacity(0.9))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(borderOverlay)
        .overlay(lockImpactOverlay)
        .scaleEffect(isCorrect && correctPulseTick > 0 ? 1.01 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: correctPulseTick)
        .modifier(TrainingShakeEffect(shakes: isWrongSelected ? wrongShakeTick : 0))
    }

    private var backgroundColor: Color {
        if isCorrect { return Color.green.opacity(0.16) }
        if isWrongSelected { return Color.red.opacity(0.16) }
        if isLockedPick { return Color.white.opacity(0.08) }
        if isSelected { return Color.orange.opacity(0.14) }
        return Color.white.opacity(0.06)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity((isSelected || isLockedPick) ? 0.22 : 0.10), lineWidth: 1)
    }

    private var lockImpactOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isLockedPick ? 0.06 : 0.0),
                        Color.white.opacity(isLockedPick ? 0.02 : 0.0),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .opacity(isLockedPick ? 1.0 : 0.0)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.green.opacity((isReveal && isCorrect) ? 0.22 : 0.0), lineWidth: 2)
                    .opacity((isReveal && isCorrect) ? 1.0 : 0.0)
            )
    }

    private func letter(for idx: Int) -> String {
        switch idx {
        case 0: return "A"
        case 1: return "B"
        case 2: return "C"
        case 3: return "D"
        default: return "\(idx + 1)"
        }
    }
}

// MARK: - Flame

private struct TrainingLoudFlame: View {
    let streak: Int
    let punch: Int

    @State private var scale: CGFloat = 1.0
    @State private var y: CGFloat = 0
    @State private var glow: CGFloat = 0.0
    @State private var burst: Bool = false
    @State private var sweep: Bool = false

    private var isLit: Bool { streak >= 3 }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(isLit ? 0.70 : 0.18),
                            Color.orange.opacity(isLit ? 0.28 : 0.06),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 52
                    )
                )
                .frame(width: 74, height: 74)
                .opacity(isLit ? 1 : 0.45)
                .scaleEffect(1.0 + glow)

            let flame = Image(systemName: "flame.fill")
                .font(DS.Typography.font(26, weight: .black, design: .default, cappedAt: 30))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.yellow.opacity(isLit ? 1.0 : 0.70),
                            Color.orange.opacity(isLit ? 1.0 : 0.60),
                            Color.red.opacity(isLit ? 0.78 : 0.38)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            flame
                .shadow(color: Color.orange.opacity(isLit ? 0.95 : 0.30), radius: isLit ? 14 : 4)
                .scaleEffect(scale)
                .offset(y: y)

            flame
                .foregroundColor(.clear)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.70))
                        .frame(width: 12, height: 52)
                        .rotationEffect(.degrees(-22))
                        .offset(x: sweep ? 24 : -24, y: -2)
                        .blur(radius: 0.8)
                        .blendMode(.screen)
                        .opacity(isLit ? 1 : 0)
                        .animation(.easeInOut(duration: 0.34), value: sweep)
                )
                .mask(flame)
                .scaleEffect(scale)
                .offset(y: y)

            if burst {
                TrainingLoudPeakBurst()
                    .offset(y: -26)
            }
        }
        .frame(width: 34, height: 34)
        .onAppear {
            if isLit {
                withAnimation(.easeInOut(duration: 1.10).repeatForever(autoreverses: true)) {
                    glow = 0.08
                }
            }
        }
        .onChange(of: streak) { _, newVal in
            withAnimation(.easeInOut(duration: 0.35)) {
                glow = (newVal >= 3) ? 0.08 : 0.0
            }
        }
        .onChange(of: punch) { _, _ in
            guard streak > 0 else { return }
            Task { @MainActor in
                await runPunch()
            }
        }
    }

    @MainActor
    private func runPunch() async {
        burst = false
        sweep = false

        withAnimation(.easeOut(duration: 0.18)) {
            scale = isLit ? 1.85 : 1.55
            y = -8
            glow = 0.18
        }
        burst = true
        sweep = true

        try? await Task.sleep(nanoseconds: 180_000_000)

        withAnimation(.easeIn(duration: 0.14)) {
            scale = 0.92
            y = 3
            glow = 0.12
        }
        try? await Task.sleep(nanoseconds: 140_000_000)

        withAnimation(.easeOut(duration: 0.16)) {
            scale = 1.18
            y = -2
            glow = 0.10
        }
        try? await Task.sleep(nanoseconds: 160_000_000)

        withAnimation(.easeOut(duration: 0.20)) {
            scale = 1.0
            y = 0
            glow = isLit ? 0.08 : 0.0
        }

        try? await Task.sleep(nanoseconds: 320_000_000)
        burst = false
    }
}

private struct TrainingLoudPeakBurst: View {
    @State private var rise: Bool = false
    @State private var fade: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.yellow.opacity(0.95),
                            Color.orange.opacity(0.70),
                            Color.red.opacity(0.42),
                            Color.clear
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 12, height: 52)
                .blur(radius: 2.1)
                .scaleEffect(x: 1.0, y: rise ? 1.35 : 0.35, anchor: .bottom)
                .opacity(fade ? 0 : 1)

            ForEach(0..<10, id: \.self) { i in
                TrainingLoudSpark(i: i, rise: rise, fade: fade)
            }
        }
        .onAppear {
            rise = false
            fade = false
            withAnimation(.easeOut(duration: 0.34)) { rise = true }
            withAnimation(.easeOut(duration: 0.38).delay(0.10)) { fade = true }
        }
    }
}

private struct TrainingLoudSpark: View {
    let i: Int
    let rise: Bool
    let fade: Bool

    private var dx: CGFloat {
        let t: [CGFloat] = [-16, -12, -8, -4, 0, 4, 8, 12, 16, 20]
        return t[i % t.count]
    }

    private var dy: CGFloat {
        let t: [CGFloat] = [-18, -22, -28, -32, -36, -30, -26, -40, -34, -44]
        return t[i % t.count]
    }

    private var s: CGFloat {
        let t: [CGFloat] = [6, 5, 6, 5, 7, 5, 6, 5, 6, 5]
        return t[i % t.count]
    }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.orange.opacity(0.98),
                        Color.red.opacity(0.60)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: s, height: s)
            .blur(radius: 0.9)
            .offset(x: rise ? dx : dx * 0.18, y: rise ? dy : 0)
            .opacity(fade ? 0 : 0.98)
            .scaleEffect(rise ? 0.70 : 1.0)
    }
}

// MARK: - Support

private struct TrainingAmbientHaze: View {
    let drift: Bool

    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.00),
                Color.white.opacity(0.035),
                Color.white.opacity(0.00)
            ],
            startPoint: drift ? .topLeading : .bottomTrailing,
            endPoint: drift ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
    }
}

private struct TrainingShakeEffect: GeometryEffect {
    var shakes: Int
    var animatableData: CGFloat

    init(shakes: Int) {
        self.shakes = shakes
        self.animatableData = CGFloat(shakes)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 6 * sin(animatableData * .pi * 2)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

private struct TrainingMiniHeat: View {
    let streak: Int

    private var pct: Double {
        min(1.0, Double(max(0, streak)) / 10.0)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: max(8, w * pct))
                    .animation(.spring(response: 0.28, dampingFraction: 0.85), value: pct)
            }
        }
    }
}

