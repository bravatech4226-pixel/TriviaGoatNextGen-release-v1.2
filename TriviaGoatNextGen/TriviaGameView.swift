//
//  TriviaGameView.swift
//  TriviaGoatNextGen
//

import SwiftUI
import UIKit
import AudioToolbox

struct TriviaGameView: View {

    @EnvironmentObject private var app: AppState

    // MARK: - Selection

    @State private var selectedIndex: Int? = nil

    // MARK: - Latches

    @State private var didLock: Bool = false
    @State private var isAdvancing: Bool = false

    // MARK: - Reveal phase

    enum RevealPhase: Equatable {
        case idle
        case suspense(choice: Int)
        case revealed(choice: Int)
    }

    @State private var phase: RevealPhase = .idle

    // MARK: - Reveal de-dupe

    @State private var lastRevealKey: String = ""

    // MARK: - Micro FX

    @State private var flashTick: Int = 0
    @State private var correctPulseTick: Int = 0
    @State private var wrongShakeTick: Int = 0

    // MARK: - Ambient / Cinematic

    @State private var hazeDrift: Bool = false
    @State private var pressurePulse: Bool = false
    @State private var questionEntranceTick: Int = 0
    @State private var pressureBannerTick: Int = 0

    // MARK: - Streak / praise tracking

    @State private var lastMilestoneTriggered: Int = 0
    @State private var flamePunchTick: Int = 0

    // MARK: - Dock state

    @State private var coachTick: Int = 0
    @State private var lastWasCorrect: Bool? = nil

    // MARK: - GOAT reward moment

    @State private var praise: PraiseMoment? = nil
    @State private var praiseTick: Int = 0

    // MARK: - Async control

    @State private var revealTask: Task<Void, Never>? = nil

    struct PraiseMoment: Equatable {
        enum Tier: Equatable {
            case building
            case locked
            case elevated
            case elite
        }

        let text: String
        let subtext: String
        let tier: Tier
        let streak: Int
    }

    // MARK: - Timing

    private let suspenseDelay: TimeInterval = 0.18
    private let revealHold: TimeInterval = 1.18

    private var totalQuestions: Int {
        max(1, app.trivia.pack.count)
    }

    private var visibleQuestionNumber: Int {
        min(max(1, app.trivia.currentIndex + 1), totalQuestions)
    }

    private var remainingQuestionsAfterCurrent: Int {
        max(0, app.trivia.pack.count - app.trivia.currentIndex - 1)
    }

    private var runProgress: Double {
        Double(visibleQuestionNumber) / Double(totalQuestions)
    }

    private var isFinalQuestion: Bool {
        remainingQuestionsAfterCurrent == 0 && !app.trivia.pack.isEmpty
    }

    private var isPressureMoment: Bool {
        guard !app.trivia.pack.isEmpty else { return false }

        let lateRunPressure = remainingQuestionsAfterCurrent <= 2
        let hotStreakPressure = app.streakCount >= 5
        let comebackOrPerfectTension = app.trivia.currentIndex >= 7 && app.trivia.score >= max(0, app.trivia.currentIndex - 1)

        return lateRunPressure || hotStreakPressure || comebackOrPerfectTension
    }

    private var pressureTitle: String {
        if isFinalQuestion { return "FINAL QUESTION" }
        if app.streakCount >= 10 { return "LEGEND RUN ACTIVE" }
        if app.streakCount >= 7 { return "ELITE PACE" }
        if app.streakCount >= 5 { return "PRESSURE RUN" }
        return "YOU’RE IN RANGE"
    }

    private var pressureSubtitle: String {
        if isFinalQuestion { return "Lock in. This one decides the finish." }
        if app.streakCount >= 7 { return "Keep the rhythm clean. Don’t rush the lock." }
        return "Momentum is building. Stay sharp."
    }

    private var hotRunToneOpacity: Double {
        if isPressureMoment { return pressurePulse ? 0.075 : 0.045 }
        return app.streakCount >= 7 ? 0.04 : 0.0
    }

    private var isRewardMomentActive: Bool {
        praise != nil
    }

    private func updateSpatialAudioMode() {
        SpatialAudioManager.shared.transition(to: isPressureMoment ? .matchPressure : .matchCalm)
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let topPadding = max(4, safeTop)
            let bottomDockReserve: CGFloat = isPressureMoment ? 128 : 112

            ZStack {
                SpaceBackground()

                AmbientHaze(drift: hazeDrift)
                    .opacity(isPressureMoment ? 0.22 : 0.16)
                    .allowsHitTesting(false)

                Color.orange
                    .ignoresSafeArea()
                    .opacity(hotRunToneOpacity)
                    .animation(.easeInOut(duration: 0.55), value: app.streakCount)
                    .animation(.easeInOut(duration: 1.2), value: pressurePulse)

                if isPressureMoment {
                    PressureAtmosphere(pulse: pressurePulse)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 8) {
                    topBar

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            if isPressureMoment {
                                PressureMomentBanner(
                                    title: pressureTitle,
                                    subtitle: pressureSubtitle,
                                    progress: runProgress,
                                    tick: pressureBannerTick
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            if let q = app.currentQuestion {
                                questionCard(q)
                                    .id("question-\(app.trivia.currentIndex)-\(questionEntranceTick)")
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity
                                    ))

                                choicesCard(q)
                                    .id("choices-\(app.trivia.currentIndex)-\(questionEntranceTick)")
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            } else {
                                emptyState
                            }
                        }
                        .padding(.top, 2)
                        .padding(.bottom, bottomDockReserve)
                        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: app.trivia.currentIndex)
                        .animation(.easeInOut(duration: 0.24), value: isPressureMoment)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .padding(.horizontal, 16)
                .padding(.top, topPadding)
                .padding(.bottom, 6)
                .allowsHitTesting(!isRewardMomentActive)
                .opacity(isRewardMomentActive ? 0.10 : 1.0)
                .blur(radius: isRewardMomentActive ? 2.5 : 0)
                .animation(.easeInOut(duration: 0.20), value: isRewardMomentActive)

                if let praise {
                    GOATMomentOverlay(
                        moment: praise,
                        trigger: praiseTick
                    )
                    .allowsHitTesting(true)
                    .transition(.opacity)
                    .zIndex(50)
                }

                Color.white
                    .ignoresSafeArea()
                    .opacity(flashTick > 0 ? 0.04 : 0.0)
                    .animation(.easeOut(duration: 0.18), value: flashTick)
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MomentumDock(
                streak: app.streakCount,
                score: app.trivia.score,
                currentIndex: app.trivia.currentIndex,
                total: app.trivia.pack.count,
                phase: phase,
                didLock: didLock,
                lastWasCorrect: lastWasCorrect,
                isPressureMoment: isPressureMoment,
                tick: coachTick
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .allowsHitTesting(!isRewardMomentActive)
            .opacity(isRewardMomentActive ? 0.08 : 1.0)
            .blur(radius: isRewardMomentActive ? 2 : 0)
            .animation(.easeInOut(duration: 0.20), value: isRewardMomentActive)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(isRewardMomentActive ? 0.88 : 0.62),
                        Color.black.opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        .onAppear {
            app.ensureTriviaRunLoaded()
            SpatialAudioManager.shared.refreshAudioState()
            updateSpatialAudioMode()

            withAnimation(.easeInOut(duration: 8.5).repeatForever(autoreverses: true)) {
                hazeDrift.toggle()
            }

            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                pressurePulse.toggle()
            }
        }
        .onDisappear {
            cancelRevealFlow()
            praise = nil
            SpatialAudioManager.shared.transition(to: .idle)
        }
        .onChange(of: app.trivia.currentIndex) { _, _ in
            resetForNewQuestion()
            questionEntranceTick += 1

            if isPressureMoment {
                pressureBannerTick += 1
            }

            updateSpatialAudioMode()
        }
        .onChange(of: app.streakCount) { _, newValue in
            handleStreakChange(newValue)

            if isPressureMoment {
                pressureBannerTick += 1
            }

            updateSpatialAudioMode()
        }
    }
}
// MARK: - UI

private extension TriviaGameView {

    var topBar: some View {
        TopBarView(
            app: app,
            punch: flamePunchTick,
            isPressureMoment: isPressureMoment,
            onBack: {
                cancelRevealFlow()
                SpatialAudioManager.shared.play(.uiTap)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    app.setRoute(.hq)
                }
            }
        )
    }

    func questionCard(_ q: TriviaQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(isFinalQuestion ? "FINAL QUESTION" : "QUESTION")
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(isPressureMoment ? .orange.opacity(0.86) : .white.opacity(0.42))
                    .tracking(1.8)

                Spacer()

                Text("Q \(visibleQuestionNumber)/\(totalQuestions)")
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(isPressureMoment ? 0.56 : 0.34))
                    .tracking(1.2)
            }

            Text(q.prompt)
                .font(DS.Typography.font(isPressureMoment ? 20 : 19, weight: .black, design: .rounded, cappedAt: 27))
                .foregroundColor(.white)
                .lineSpacing(1.4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(isPressureMoment ? 16 : 15)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(isPressureMoment ? 0.88 : 0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isPressureMoment ? Color.orange.opacity(pressurePulse ? 0.24 : 0.14) : Color.white.opacity(0.10),
                    lineWidth: isPressureMoment ? 1.35 : 1
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isPressureMoment ? 0.045 : 0.03),
                            Color.clear,
                            Color.orange.opacity(isPressureMoment ? 0.04 : 0.015)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: .black.opacity(0.30), radius: 18, x: 0, y: 11)
        .shadow(color: .orange.opacity(isPressureMoment ? 0.08 : 0.0), radius: 22, x: 0, y: 12)
    }

    func choicesCard(_ q: TriviaQuestion) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(q.choices.enumerated()), id: \.offset) { idx, title in
                ChoiceRowView(
                    idx: idx,
                    title: title,
                    correctIndex: q.correctIndex,
                    selectedIndex: selectedIndex,
                    phase: phase,
                    isPressureMoment: isPressureMoment,
                    correctPulseTick: correctPulseTick,
                    wrongShakeTick: wrongShakeTick
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canTapChoice else { return }
                    SpatialAudioManager.shared.play(.uiTap)

                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        selectedIndex = idx
                    }
                }
            }

            Button {
                lockOrAdvance(question: q)
            } label: {
                HStack(spacing: 9) {
                    if didLock {
                        Image(systemName: "arrow.forward.circle.fill")
                            .font(DS.Typography.font(15, weight: .black, design: .default, cappedAt: 18))
                    }

                    Text(didLock ? "ADVANCE" : (isPressureMoment ? "LOCK THE MOMENT" : "LOCK IN"))
                        .font(DS.Typography.font(15, weight: .black, design: .rounded, cappedAt: 19))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(ChunkyButtonStyle(color: didLock ? .white.opacity(0.18) : .orange))
            .disabled(((selectedIndex == nil) && !didLock) || isAdvancing || isRewardMomentActive)
            .padding(.top, 4)
            .pressScale()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(isPressureMoment ? 0.82 : 0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.orange.opacity(isPressureMoment ? 0.14 : 0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isPressureMoment ? 0.26 : 0.0), radius: 14, x: 0, y: 9)
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
            Text("LOADING…")
                .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 15))
                .foregroundColor(.white.opacity(0.5))
                .tracking(2)

            Button {
                cancelRevealFlow()
                SpatialAudioManager.shared.play(.uiTap)
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
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.top, 40)
    }
}

// MARK: - Streak Moments

private extension TriviaGameView {

    func handleStreakChange(_ newValue: Int) {
        let milestones: Set<Int> = [3, 5, 7, 10]
        guard milestones.contains(newValue) else { return }
        guard newValue != lastMilestoneTriggered else { return }

        lastMilestoneTriggered = newValue
        flamePunchTick += 1

        SpatialAudioManager.shared.playStreakMilestone()

        if let moment = praiseMoment(for: newValue) {
            presentPraise(moment)
        }
    }

    private func praiseMoment(for streak: Int) -> PraiseMoment? {
        switch streak {
        case 3:
            return PraiseMoment(
                text: "MOMENTUM BUILDING",
                subtext: "The GOAT approves this run.",
                tier: .building,
                streak: streak
            )
        case 5:
            return PraiseMoment(
                text: "RHYTHM LOCKED",
                subtext: "Clean answers. Calm pressure.",
                tier: .locked,
                streak: streak
            )
        case 7:
            return PraiseMoment(
                text: "STRONG RUN",
                subtext: "You’re entering elite territory.",
                tier: .elevated,
                streak: streak
            )
        case 10:
            return PraiseMoment(
                text: "ELITE PACE",
                subtext: "This is premium-level play.",
                tier: .elite,
                streak: streak
            )
        default:
            return nil
        }
    }

    private func presentPraise(_ moment: PraiseMoment) {
        praise = moment
        praiseTick += 1

        let expectedTick = praiseTick

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.85) {
            if praiseTick == expectedTick, praise?.streak == moment.streak {
                praise = nil
            }
        }
    }
}

// MARK: - Actions

private extension TriviaGameView {
    
    func questionIdentity(_ q: TriviaQuestion?) -> String {
        guard let q else { return "nil" }

        return [
            q.prompt,
            q.choices.joined(separator: "|"),
            "\(q.correctIndex)",
            "\(app.trivia.currentIndex)"
        ].joined(separator: "||")
    }

    func lockOrAdvance(question q: TriviaQuestion) {
        guard !isAdvancing else { return }
        guard !isRewardMomentActive else { return }

        if didLock {
            SpatialAudioManager.shared.play(.uiTap)
            advance()
            return
        }

        guard let idx = selectedIndex else { return }

        cancelRevealFlow()

        didLock = true
        isAdvancing = true

        SpatialAudioManager.shared.play(.lockIn)
        flashTick += 1

        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            phase = .suspense(choice: idx)
        }

        app.submitAnswer(index: idx)

        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(suspenseDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard didLock else { return }
            guard questionIdentity(app.currentQuestion) == questionIdentity(q) else { return }

            fireRevealFX(question: q, picked: idx)

            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                phase = .revealed(choice: idx)
            }

            let hold = isPressureMoment ? revealHold + 0.12 : revealHold
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))

            guard !Task.isCancelled else { return }
            guard didLock else { return }
            guard questionIdentity(app.currentQuestion) == questionIdentity(q) else { return }

            while praise != nil && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000)
            }

            guard !Task.isCancelled else { return }
            guard didLock else { return }
            guard questionIdentity(app.currentQuestion) == questionIdentity(q) else { return }

            advance()
        }
    }

    func advance() {
        guard praise == nil else { return }

        cancelRevealFlow(keepVisualState: true)

        HapticManager.instance.impact(isPressureMoment ? .rigid : .medium)

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
            correctPulseTick += 1
        } else {
            SpatialAudioManager.shared.play(.wrong)
            wrongShakeTick += 1
        }
    }

    func resetForNewQuestion() {
        cancelRevealFlow()

        praise = nil

        selectedIndex = nil
        didLock = false
        isAdvancing = false
        lastRevealKey = ""
        phase = .idle
        flashTick = 0
        correctPulseTick = 0
        wrongShakeTick = 0
        lastWasCorrect = nil
        coachTick += 1
    }

    func cancelRevealFlow(keepVisualState: Bool = false) {
        revealTask?.cancel()
        revealTask = nil

        if !keepVisualState {
            isAdvancing = false
        }
    }
}
// MARK: - Pressure Moment Banner

private struct PressureMomentBanner: View {
    let title: String
    let subtitle: String
    let progress: Double
    let tick: Int

    @State private var glow = false
    @State private var entranceScale: CGFloat = 0.98

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(glow ? 0.26 : 0.14))
                        .frame(width: 36, height: 36)

                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.orange.opacity(0.94))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 15))
                        .foregroundColor(.white.opacity(0.96))
                        .tracking(1.7)

                    Text(subtitle)
                        .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                }

                Spacer()
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let fill = max(22, width * min(max(progress, 0), 1))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 7)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.92),
                                    Color.white.opacity(0.70)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fill, height: 7)
                        .shadow(color: .orange.opacity(0.18), radius: 8, x: 0, y: 0)
                }
            }
            .frame(height: 7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(Color.black.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(Color.orange.opacity(glow ? 0.28 : 0.14), lineWidth: 1.2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.025),
                            Color.clear,
                            Color.orange.opacity(0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .scaleEffect(entranceScale)
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 9)
        .onAppear {
            entranceScale = 0.98

            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                glow.toggle()
            }

            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                entranceScale = 1.0
            }
        }
        .onChange(of: tick) { _, _ in
            entranceScale = 0.985
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                entranceScale = 1.0
            }
        }
    }
}

// MARK: - Pressure Atmosphere

private struct PressureAtmosphere: View {
    let pulse: Bool

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.orange.opacity(pulse ? 0.12 : 0.07),
                    Color.orange.opacity(pulse ? 0.040 : 0.025),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 18,
                endRadius: 360
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.05),
                    Color.orange.opacity(pulse ? 0.035 : 0.018),
                    Color.black.opacity(0.11)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 1.2), value: pulse)
    }
}

// MARK: - GOAT Reward Moment

private struct GOATMomentOverlay: View {
    let moment: TriviaGameView.PraiseMoment
    let trigger: Int

    @State private var mascotScale: CGFloat = 0.78
    @State private var mascotYOffset: CGFloat = 42
    @State private var mascotRotation: Double = 0
    @State private var textYOffset: CGFloat = 18

    @State private var cardOpacity: Double = 0.0
    @State private var haloOpacity: Double = 0.0
    @State private var dimOpacity: Double = 0.0
    @State private var glowSweep: Bool = false
    @State private var hopY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let centerY = geo.size.height * 0.50

            ZStack {
                Color.black
                    .opacity(dimOpacity)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        haloColor.opacity(haloOpacity),
                        haloColor.opacity(haloOpacity * 0.34),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 16,
                    endRadius: 280
                )
                .frame(width: 460, height: 460)
                .position(x: geo.size.width / 2, y: centerY - 24)

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        haloColor.opacity(0.34),
                                        haloColor.opacity(0.12),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 132
                                )
                            )
                            .frame(width: 240, height: 240)

                        Image("tg_mascot")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 270)
                            .shadow(color: haloColor.opacity(0.24), radius: 28, x: 0, y: 16)
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(0.24))
                                    .frame(width: 34, height: 300)
                                    .blur(radius: 6)
                                    .rotationEffect(.degrees(-18))
                                    .offset(x: glowSweep ? 126 : -126)
                                    .opacity(0.50)
                                    .mask(
                                        Image("tg_mascot")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 270)
                                    )
                            )
                    }
                    .scaleEffect(mascotScale)
                    .offset(y: mascotYOffset + hopY)
                    .rotationEffect(.degrees(mascotRotation))

                    VStack(spacing: 6) {
                        Text(moment.text)
                            .font(DS.Typography.font(28, weight: .black, design: .rounded, cappedAt: 34))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.98),
                                        haloColor.opacity(0.90)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .multilineTextAlignment(.center)

                        Text(moment.subtext)
                            .font(DS.Typography.font(14, weight: .semibold, design: .rounded, cappedAt: 18))
                            .foregroundColor(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black.opacity(0.74))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .offset(y: textYOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(cardOpacity)
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
        case .building, .locked, .elite:
            return .orange
        case .elevated:
            return .white
        }
    }

    private func runSequence() {
        mascotScale = 0.78
        mascotYOffset = 42
        mascotRotation = -3
        textYOffset = 18

        cardOpacity = 0.0
        haloOpacity = 0.0
        dimOpacity = 0.0
        glowSweep = false
        hopY = 0

        withAnimation(.easeOut(duration: 0.20)) {
            dimOpacity = 0.90
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            mascotScale = 1.02
            mascotYOffset = 0
            mascotRotation = 0
            textYOffset = 0
            cardOpacity = 1.0
            haloOpacity = 0.30
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                mascotScale = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            glowSweep = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            runHop()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.10) {
            withAnimation(.easeOut(duration: 0.55)) {
                cardOpacity = 0.0
                haloOpacity = 0.0
                dimOpacity = 0.0
                mascotScale = 1.03
                mascotYOffset = -6
            }
        }
    }

    private func runHop() {
        let offsets: [CGFloat] = [-18, 0, -10, 0]

        for (index, value) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.10 * Double(index))) {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                    hopY = value
                }
            }
        }
    }
}
// MARK: - Top Bar View

private struct TopBarView: View {
    let app: AppState
    let punch: Int
    let isPressureMoment: Bool
    let onBack: () -> Void

    var body: some View {
        let raw = (app.trivia.topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let isTrainingRun = raw.uppercased().hasPrefix("TRAINING")
        let isDailyMissionRun = raw.uppercased().hasPrefix("DAILY MISSION")

        let cleanedTopic = raw
            .replacingOccurrences(of: "TRAINING:", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "Daily Mission:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let topicTitle = cleanedTopic.isEmpty ? "GENERAL KNOWLEDGE" : cleanedTopic.uppercased()
        let modeTitle = isTrainingRun ? "TRAINING ARENA" : (isDailyMissionRun ? "DAILY MISSION" : "MISSION")
        let total = max(1, app.trivia.pack.count)
        let current = min(max(1, app.trivia.currentIndex + 1), total)

        return HStack(alignment: .center, spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .pressScale()

            VStack(alignment: .leading, spacing: 3) {
                Text(modeTitle)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(isPressureMoment ? .orange.opacity(0.76) : .white.opacity(0.46))
                    .tracking(1.9)

                Text(topicTitle)
                    .font(DS.Typography.font(15, weight: .black, design: .rounded, cappedAt: 20))
                    .foregroundColor(.white.opacity(0.96))
                    .lineLimit(2)
                    .minimumScaleFactor(0.80)

                Text("QUESTION \(current)/\(total)")
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.34))
                    .tracking(1.2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                Text("SCORE \(app.trivia.score)")
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.72))
                    .tracking(1.0)

                HStack(spacing: 6) {
                    LoudFlame(
                        streak: app.streakCount,
                        punch: punch
                    )

                    Text("\(app.streakCount)")
                        .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                        .foregroundColor(.white.opacity(0.94))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isPressureMoment ? 0.065 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isPressureMoment ? Color.orange.opacity(0.14) : Color.white.opacity(0.10), lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Momentum Dock

private struct MomentumDock: View {
    let streak: Int
    let score: Int
    let currentIndex: Int
    let total: Int
    let phase: TriviaGameView.RevealPhase
    let didLock: Bool
    let lastWasCorrect: Bool?
    let isPressureMoment: Bool
    let tick: Int

    @State private var pulse: Bool = false
    @State private var flash: Bool = false

    var body: some View {
        let t = max(1, total)
        let q = min(max(1, currentIndex + 1), t)
        let progress = Double(q) / Double(t)

        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(DS.Typography.font(15, weight: .black, design: .rounded, cappedAt: 19))
                        .foregroundColor(.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text("STREAK \(streak) • SCORE \(score)")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.56))
                        .tracking(1.1)
                }

                Spacer()

                Text("Q \(q)/\(t)")
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.60))
                    .tracking(1.2)
            }

            GeometryReader { proxy in
                let totalWidth = proxy.size.width
                let fillWidth = max(18, totalWidth * progress)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 10)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.98),
                                    Color.white.opacity(isPressureMoment ? 0.72 : 0.10),
                                    Color.orange.opacity(0.80)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: 10)
                        .shadow(color: .orange.opacity(isPressureMoment ? 0.30 : 0.24), radius: 10, x: 0, y: 0)
                }
            }
            .frame(height: 10)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.orange.opacity(pulse ? (isPressureMoment ? 0.42 : 0.30) : (isPressureMoment ? 0.22 : 0.14)), lineWidth: 1.4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(flash ? 0.06 : 0.0))
                )
                .shadow(color: .black.opacity(0.60), radius: 22, x: 0, y: 14)
                .shadow(color: .orange.opacity(isPressureMoment ? 0.16 : 0.10), radius: 20, x: 0, y: 12)
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
                return "LOCKED IN…"
            case .revealed:
                if lastWasCorrect == true { return "CORRECT" }
                if lastWasCorrect == false { return "MISS — NEXT UP" }
                return "CONFIRMED"
            case .idle:
                break
            }
        }

        if isPressureMoment && streak >= 7 { return "ELITE PRESSURE RUN" }
        if isPressureMoment { return "PRESSURE MOMENT" }
        if streak >= 10 { return "LEGEND RUN" }
        if streak >= 7  { return "WHO'S THE GOAT NOW?" }
        if streak >= 5  { return "STRONG RUN" }
        if streak >= 3  { return "MOMENTUM BUILDING" }

        if lastWasCorrect == false { return "RESET AND GO AGAIN" }
        if lastWasCorrect == true  { return "NICE — KEEP GOING" }

        return "ONE CLEAN ANSWER AT A TIME"
    }
}

// MARK: - Loud Flame

private struct LoudFlame: View {
    let streak: Int
    let punch: Int

    @State private var scale: CGFloat = 1.0
    @State private var y: CGFloat = 0
    @State private var glow: CGFloat = 0.0
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
        .onChange(of: streak) { _, _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                scale = 1.08
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = 1.0
                }
            }
        }
        .onChange(of: punch) { _, _ in
            guard streak > 0 else { return }

            sweep = false

            withAnimation(.easeOut(duration: 0.16)) {
                scale = isLit ? 1.22 : 1.12
                y = -4
                glow = isLit ? 0.16 : 0.10
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                sweep = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.easeIn(duration: 0.12)) {
                    scale = 0.96
                    y = 2
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                withAnimation(.easeOut(duration: 0.18)) {
                    scale = 1.0
                    y = 0
                    glow = isLit ? 0.08 : 0.0
                }
            }
        }
    }
}

// MARK: - Choice Row

private struct ChoiceRowView: View {
    let idx: Int
    let title: String
    let correctIndex: Int
    let selectedIndex: Int?
    let phase: TriviaGameView.RevealPhase
    let isPressureMoment: Bool
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
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconFill)
                    .frame(width: 26, height: 26)

                Text(letter(for: idx))
                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(iconForeground)
            }

            Text(title)
                .font(DS.Typography.font(14, weight: .bold, design: .rounded, cappedAt: 18))
                .foregroundColor(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if isReveal && isCorrect {
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.Typography.font(17, weight: .bold, design: .default, cappedAt: 20))
                    .foregroundColor(.green.opacity(0.9))
            } else if isReveal && isWrongSelected {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Typography.font(17, weight: .bold, design: .default, cappedAt: 20))
                    .foregroundColor(.red.opacity(0.9))
            } else if isSelected {
                Image(systemName: "circle.fill")
                    .font(DS.Typography.font(9, weight: .black, design: .default, cappedAt: 11))
                    .foregroundColor(.orange.opacity(0.9))
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(borderOverlay)
        .overlay(lockImpactOverlay)
        .scaleEffect(isCorrect && correctPulseTick > 0 ? 1.01 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: correctPulseTick)
        .modifier(ShakeEffect(shakes: isWrongSelected ? wrongShakeTick : 0))
    }

    private var iconFill: Color {
        if isCorrect { return .green.opacity(0.18) }
        if isWrongSelected { return .red.opacity(0.18) }
        if isLockedPick || isSelected { return .orange.opacity(isPressureMoment ? 0.24 : 0.18) }
        return .white.opacity(0.06)
    }

    private var iconForeground: Color {
        if isCorrect { return .green.opacity(0.95) }
        if isWrongSelected { return .red.opacity(0.92) }
        if isLockedPick || isSelected { return .orange.opacity(0.95) }
        return .white.opacity(0.62)
    }

    private var backgroundColor: Color {
        if isCorrect { return Color.green.opacity(0.16) }
        if isWrongSelected { return Color.red.opacity(0.16) }
        if isLockedPick { return Color.white.opacity(0.08) }
        if isSelected { return Color.orange.opacity(isPressureMoment ? 0.18 : 0.14) }
        return Color.white.opacity(0.06)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(
                (isSelected || isLockedPick)
                ? Color.orange.opacity(isPressureMoment ? 0.26 : 0.22)
                : Color.white.opacity(0.10),
                lineWidth: 1
            )
    }

    private var lockImpactOverlay: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
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
                RoundedRectangle(cornerRadius: 15, style: .continuous)
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

// MARK: - Ambient Haze

private struct AmbientHaze: View {
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

// MARK: - Shake

private struct ShakeEffect: GeometryEffect {
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
