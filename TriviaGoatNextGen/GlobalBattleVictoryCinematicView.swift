//
//  GlobalBattleVictoryCinematicView.swift
//  TriviaGoatNextGen
//
//  PREMIUM BRAND CINEMATIC
//

import SwiftUI
import Foundation
import UIKit

struct GlobalBattleVictoryCinematicView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let winnerName: String
    let winnerScore: Int
    let finishOutcome: GlobalBattleSession.FinishOutcome
    let onContinue: () -> Void

    private enum Phase: Equatable {
        case idle
        case verdictBoot
        case inbound
        case warp
        case pressureHold
        case impact
        case heroReveal
        case coronation
        case scoreReveal
        case settled
    }

    @State private var isActive = true
    @State private var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var phase: Phase = .idle
    @State private var directorTask: Task<Void, Never>? = nil

    @State private var pulse = false
    @State private var pulseLoopStarted = false
    @State private var starDrift: CGFloat = 0
    @State private var sceneGlow: Double = 0
    @State private var cameraScale: CGFloat = 0.82
    @State private var cameraRotation: Double = -5
    @State private var cameraTilt: Double = 10
    @State private var shakeX: CGFloat = 0
    @State private var shakeY: CGFloat = 0

    @State private var warpOpacity: Double = 0
    @State private var pressureOpacity: Double = 0
    @State private var impactFlash: Double = 0
    @State private var lensOpacity: Double = 0
    @State private var shockwave = false

    @State private var heroVisible = false
    @State private var heroScale: CGFloat = 0.42
    @State private var heroLift: CGFloat = 18
    @State private var crownVisible = false
    @State private var crownScale: CGFloat = 0.3
    @State private var nameVisible = false
    @State private var scoreVisible = false
    @State private var allowContinue = false
    @State private var didContinue = false

    private let heavyHaptics = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidHaptics = UIImpactFeedbackGenerator(style: .rigid)
    private let successHaptics = UINotificationFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let screenWidth = max(1, geo.size.width)
            let screenHeight = max(1, geo.size.height)
            let contentMaxWidth = max(1, screenWidth - 32)
            let stageWidth = min(screenWidth, 430)
            let stageHeight = min(max(260, screenHeight * 0.46), 390)
            let stageScale = min(1.0, max(0.72, stageWidth / 390))

            ZStack {
                backgroundLayer

                VStack(spacing: 0) {
                    headerHUD
                        .padding(.top, max(28, geo.safeAreaInsets.top + 16))
                        .padding(.horizontal, 24)
                        .frame(maxWidth: contentMaxWidth)

                    Spacer(minLength: 16)

                    ZStack {
                        galaxyCore
                        trophyChamber
                        pressureLayer
                        warpLayer
                        heroLayer
                        ShockwaveCircle(active: shockwave, color: accent)
                    }
                    .scaleEffect(stageScale)
                    .frame(width: stageWidth, height: stageHeight, alignment: .center)
                    .clipped()
                    .scaleEffect(cameraScale)
                    .rotationEffect(.degrees(cameraRotation))
                    .rotation3DEffect(
                        .degrees(cameraTilt),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.75
                    )
                    .offset(x: shakeX, y: shakeY)

                    Spacer(minLength: 10)

                    resultHUD
                        .padding(.horizontal, 24)
                        .frame(maxWidth: contentMaxWidth)

                    continueButton
                        .frame(maxWidth: contentMaxWidth)
                        .padding(.horizontal, 26)
                        .padding(.top, 20)
                        .padding(.bottom, max(34, geo.safeAreaInsets.bottom + 22))
                }

                LensStreakView(width: screenWidth, color: accent.opacity(0.56))
                    .opacity(lensOpacity)

                Color.white
                    .opacity(impactFlash)
                    .ignoresSafeArea()
            }
            .frame(width: screenWidth, height: screenHeight, alignment: .center)
            .clipped()
            .background(Color.black)
            .statusBar(hidden: true)
        }
        .onAppear {
            isActive = true
            isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

            heavyHaptics.prepare()
            rigidHaptics.prepare()
            successHaptics.prepare()

            runDirector()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onDisappear {
            isActive = false
            directorTask?.cancel()
            directorTask = nil
            pulse = false
            pulseLoopStarted = false
        }
    }
}

// MARK: - HUD

private extension GlobalBattleVictoryCinematicView {

    var headerHUD: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(accent.opacity(0.44))
                    .frame(width: 42, height: 2)

                Circle()
                    .fill(accent.opacity(pulse ? 1 : 0.42))
                    .frame(width: 7, height: 7)

                Capsule()
                    .fill(accent.opacity(0.44))
                    .frame(width: 42, height: 2)
            }

            Text(headerText)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(accent.opacity(0.94))
                .tracking(3.6)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule().fill(Color.black.opacity(0.46))
        )
        .overlay(
            Capsule().stroke(accent.opacity(0.24), lineWidth: 1)
        )
        .opacity(phase == .idle ? 0 : 1)
        .animation(.easeOut(duration: 0.35), value: phase)
    }

    var trophyChamber: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.0),
                            accent.opacity(0.22 + sceneGlow * 0.16),
                            Color.white.opacity(0.08),
                            accent.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: 292, height: 292)
                .rotationEffect(.degrees(isLowPowerMode ? 0 : (pulse ? 3 : -3)))
                .opacity(heroVisible ? 1 : 0.55)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
                .frame(width: 238, height: 238)
                .rotationEffect(.degrees(isLowPowerMode ? 0 : (pulse ? -5 : 5)))
        }
    }

    var resultHUD: some View {
        VStack(spacing: 14) {
            Text(outcomeTitle)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(accent.opacity(0.96))
                .tracking(2.2)
                .opacity(nameVisible ? 1 : 0)

            Text(winnerLabel)
                .font(.system(size: heroShowsNoWinnerState ? 28 : 32, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .opacity(nameVisible ? 1 : 0)
                .scaleEffect(nameVisible ? 1 : 0.92)

            if scoreVisible {
                VStack(spacing: 10) {
                    Text(scoreline)
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.90))

                    Text(outcomeSubtitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                )
            }
        }
    }

    var continueButton: some View {
        Button {
            continueToHQ()
        } label: {
            Text("RETURN TO HQ")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.white, accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
        }
        .buttonStyle(PrimaryButtonStyle())
        .opacity(allowContinue ? 1 : 0)
        .scaleEffect(allowContinue ? 1 : 0.94)
        .allowsHitTesting(allowContinue)
    }
}

// MARK: - Stage

private extension GlobalBattleVictoryCinematicView {

    var backgroundLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [
                    accent.opacity(0.10 + sceneGlow * 0.24),
                    Color.black.opacity(0.78),
                    Color.black
                ],
                center: .center,
                startRadius: 20,
                endRadius: 680
            )
            .ignoresSafeArea()

            if ambientParticlesEnabled {
                ParticleField(
                    particles: BackgroundStar.smallStars,
                    accent: accent,
                    pulse: pulse,
                    intensity: 0.72
                )
                .offset(x: -starDrift * 24, y: starDrift * 10)

                ParticleField(
                    particles: BackgroundStar.largeStars,
                    accent: accent,
                    pulse: !pulse,
                    intensity: 1.0
                )
                .offset(x: -starDrift * 46, y: starDrift * 14)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.58),
                    Color.clear,
                    Color.black.opacity(0.84)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    var galaxyCore: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(0.36 + sceneGlow * 0.20),
                            accent.opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 206
                    )
                )
                .frame(width: 370, height: 370)
                .blur(radius: galaxyBlurRadius)

            ForEach(0..<5, id: \.self) { idx in
                Circle()
                    .stroke(
                        accent.opacity(0.08 + Double(idx) * 0.026),
                        lineWidth: idx == 0 ? 1.6 : 1.0
                    )
                    .frame(
                        width: CGFloat(164 + idx * 44),
                        height: CGFloat(164 + idx * 44)
                    )
                    .scaleEffect(isLowPowerMode ? 1.0 : (pulse ? 1.025 : 0.985))
            }
        }
    }

    var pressureLayer: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.48), lineWidth: 2)
                .frame(width: 210, height: 210)
                .scaleEffect(pressureOpacity > 0 ? 1.34 : 0.68)
                .opacity(pressureOpacity)

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .frame(width: 286, height: 286)
                .scaleEffect(pressureOpacity > 0 ? 1.18 : 0.80)
                .opacity(pressureOpacity * 0.75)

            Text(pressureText)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.76))
                .tracking(2.0)
                .opacity(pressureOpacity)
                .offset(y: 166)
        }
    }

    var warpLayer: some View {
        ZStack {
            ForEach(activeWarpLines, id: \.id) { line in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                accent.opacity(0.24),
                                .white.opacity(0.90)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: line.width, height: line.length)
                    .rotationEffect(.degrees(line.rotation))
                    .offset(x: line.x, y: line.y + starDrift * 178)
                    .opacity(warpOpacity * line.opacity)
                    .blur(radius: 0.6)
            }
        }
    }

    var heroLayer: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(heroVisible ? 0.34 : 0),
                            accent.opacity(heroVisible ? 0.12 : 0),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 184
                    )
                )
                .frame(width: 340, height: 340)
                .blur(radius: heroAuraBlurRadius)
                .scaleEffect(premiumMotionEnabled ? (pulse ? 1.10 : 0.92) : 1.0)

            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.95))
                    .frame(width: 158, height: 158)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.98), lineWidth: 2.7)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                            .frame(width: 178, height: 178)
                    )
                    .shadow(color: accent.opacity(heroVisible ? 0.72 : 0), radius: heroShadowRadius)

                Circle()
                    .trim(from: 0.08, to: 0.88)
                    .stroke(
                        accent.opacity(0.44),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 192, height: 192)
                    .rotationEffect(.degrees(premiumMotionEnabled ? (pulse ? 28 : -8) : 0))
                    .opacity(heroVisible ? 1 : 0)

                if heroShowsNoWinnerState {
                    Image(systemName: "nosign")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundColor(accent.opacity(0.98))
                } else {
                    Text(heroInitial)
                        .font(.system(size: 80, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: accent.opacity(0.5), radius: 16)
                }

                if crownVisible && !heroShowsNoWinnerState {
                    Image(systemName: crownIcon)
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(crownColor)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.black.opacity(0.94)))
                        .overlay(Capsule().stroke(accent.opacity(0.48), lineWidth: 1))
                        .offset(y: -104)
                        .scaleEffect(crownScale)
                        .shadow(color: crownColor.opacity(0.45), radius: 14)
                }
            }
            .scaleEffect(heroScale)
            .offset(y: heroLift)
            .opacity(heroVisible ? 1 : 0)
        }
    }
}

// MARK: - Text + Outcome

private extension GlobalBattleVictoryCinematicView {

    var premiumMotionEnabled: Bool {
        isActive && !isLowPowerMode && !reduceMotion
    }

    var ambientParticlesEnabled: Bool {
        premiumMotionEnabled && phase != .settled
    }

    var galaxyBlurRadius: CGFloat {
        premiumMotionEnabled ? 28 : 8
    }

    var heroAuraBlurRadius: CGFloat {
        premiumMotionEnabled ? 26 : 8
    }

    var heroShadowRadius: CGFloat {
        premiumMotionEnabled ? 34 : 14
    }

    var activeWarpLines: [WarpLine] {
        premiumMotionEnabled ? WarpLine.lines : Array(WarpLine.lines.prefix(5))
    }

    var accent: Color {
        switch finishOutcome {
        case .tieBreakSpeedWin:
            return .yellow
        case .doubleDisqualification:
            return .red
        case .winByDisqualification:
            return .orange
        case .regulationWin, .none:
            return .orange
        }
    }

    var crownColor: Color {
        switch finishOutcome {
        case .tieBreakSpeedWin:
            return .yellow
        case .winByDisqualification:
            return .orange
        default:
            return .yellow
        }
    }

    var crownIcon: String {
        switch finishOutcome {
        case .tieBreakSpeedWin:
            return "bolt.fill"
        case .winByDisqualification:
            return "shield.fill"
        default:
            return "crown.fill"
        }
    }

    var heroShowsNoWinnerState: Bool {
        if case .doubleDisqualification = finishOutcome { return true }
        return false
    }

    var winnerLabel: String {
        if heroShowsNoWinnerState { return "NO PILOT RETURNED" }

        let clean = winnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "PILOT" : clean.uppercased()
    }

    var heroInitial: String {
        let clean = winnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = String(clean.prefix(1)).uppercased()
        return first.isEmpty ? "P" : first
    }

    var headerText: String {
        switch phase {
        case .verdictBoot:
            return "FINAL VERDICT INCOMING"
        case .inbound, .warp:
            return "VICTOR VECTOR LOCKED"
        case .pressureHold:
            return "PRESSURE WINDOW COLLAPSING"
        case .impact, .heroReveal:
            return "HOME BASE IMPACT"
        case .coronation:
            return heroShowsNoWinnerState ? "ARENA SEALED" : "CROWN SEQUENCE ARMED"
        case .scoreReveal, .settled:
            return outcomeTitle
        case .idle:
            return ""
        }
    }

    var pressureText: String {
        switch finishOutcome {
        case .tieBreakSpeedWin:
            return "SPEED DECIDES"
        case .doubleDisqualification:
            return "NO SURVIVORS"
        case .winByDisqualification:
            return "SURVIVAL CHECK"
        default:
            return "VICTORY CHECK"
        }
    }

    var outcomeTitle: String {
        switch finishOutcome {
        case .regulationWin:
            return "REGULATION VICTORY"
        case .tieBreakSpeedWin:
            return "TIE-BREAK SPEED WIN"
        case .winByDisqualification(_, _, let duringTieBreak):
            return duringTieBreak ? "TIE-BREAK SURVIVAL WIN" : "DISQUALIFICATION WIN"
        case .doubleDisqualification:
            return "DOUBLE DISQUALIFICATION"
        case .none:
            return "BATTLE COMPLETE"
        }
    }

    var outcomeSubtitle: String {
        switch finishOutcome {
        case .regulationWin:
            return "The final standings are locked. The arena has its winner."
        case .tieBreakSpeedWin:
            return "The fastest correct answer broke the deadlock."
        case .winByDisqualification(_, _, let duringTieBreak):
            return duringTieBreak
                ? "The tie-break pressure eliminated the field."
                : "Missed-answer pressure ended the chase."
        case .doubleDisqualification:
            return "No pilot survived the final pressure sequence."
        case .none:
            return "The match is complete."
        }
    }

    var scoreline: String {
        heroShowsNoWinnerState
            ? "ARENA LOCKED"
            : "\(winnerScore) PTS • HOME BASE REACHED"
    }
}

// MARK: - Director

private extension GlobalBattleVictoryCinematicView {

    func runDirector() {
        guard directorTask == nil else { return }

        if !premiumMotionEnabled {
            runReducedPowerDirector()
            return
        }

        directorTask = Task {
            await MainActor.run {
                phase = .verdictBoot
                pulse = false
                pulseLoopStarted = false
                starDrift = 0
                sceneGlow = 0.08
                cameraScale = 0.80
                cameraRotation = -5
                cameraTilt = 10
                shakeX = 0
                shakeY = 0
                warpOpacity = 0
                pressureOpacity = 0
                impactFlash = 0
                lensOpacity = 0
                shockwave = false
                heroVisible = false
                heroScale = 0.42
                heroLift = 18
                crownVisible = false
                crownScale = 0.30
                nameVisible = false
                scoreVisible = false
                allowContinue = false
                didContinue = false

                startPulseLoopIfNeeded()
            }

            try? await Task.sleep(nanoseconds: 520_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                rigidHaptics.impactOccurred(intensity: 0.45)
                phase = .inbound

                withAnimation(.easeInOut(duration: 0.72)) {
                    starDrift = 0.32
                    sceneGlow = 0.22
                    cameraScale = 0.94
                    cameraRotation = -2
                    cameraTilt = 6
                }
            }

            try? await Task.sleep(nanoseconds: 720_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                heavyHaptics.impactOccurred(intensity: 0.70)
                phase = .warp

                withAnimation(.easeIn(duration: 0.66)) {
                    warpOpacity = 1
                    starDrift = 1.08
                    sceneGlow = 0.42
                    cameraScale = 1.18
                    cameraRotation = 1.5
                    cameraTilt = 2
                }
            }

            try? await Task.sleep(nanoseconds: 640_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                phase = .pressureHold
                SpatialAudioManager.shared.play(.dangerPulse)
                rigidHaptics.impactOccurred(intensity: 0.75)

                withAnimation(.easeInOut(duration: 0.56)) {
                    pressureOpacity = 1
                    cameraScale = 1.08
                    cameraRotation = 0
                    cameraTilt = 0
                    sceneGlow = 0.58
                }
            }

            try? await Task.sleep(nanoseconds: 650_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                phase = .impact
                heavyHaptics.impactOccurred(intensity: 1.0)

                withAnimation(.easeIn(duration: 0.08)) {
                    impactFlash = 0.92
                    lensOpacity = 1
                    shakeX = 16
                    shakeY = -9
                }
            }

            try? await Task.sleep(nanoseconds: 92_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                phase = .heroReveal
                shockwave = false
                heroVisible = true
                warpOpacity = 0
                pressureOpacity = 0
                shakeX = 0
                shakeY = 0
                shockwave = true

                withAnimation(.spring(response: 0.54, dampingFraction: 0.68)) {
                    impactFlash = 0
                    lensOpacity = 0
                    heroScale = 1.12
                    heroLift = 0
                    cameraScale = 1.0
                    sceneGlow = 0.68
                }
            }

            try? await Task.sleep(nanoseconds: 560_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.32)) {
                    heroScale = 1.0
                }
            }

            try? await Task.sleep(nanoseconds: 240_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                phase = .coronation
                successHaptics.notificationOccurred(heroShowsNoWinnerState ? .warning : .success)

                if !heroShowsNoWinnerState {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.68)) {
                        crownVisible = true
                        crownScale = 1.16
                    }
                }

                withAnimation(.easeOut(duration: 0.42)) {
                    nameVisible = true
                }
            }

            try? await Task.sleep(nanoseconds: 210_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    crownScale = 1.0
                }
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                phase = .scoreReveal
                rigidHaptics.impactOccurred(intensity: 0.55)

                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    scoreVisible = true
                    sceneGlow = 0.44
                }
            }

            try? await Task.sleep(nanoseconds: 820_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                phase = .settled
                pulse = false
                sceneGlow = 0.32
            }

            try? await Task.sleep(nanoseconds: 240_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                    allowContinue = true
                }

                directorTask = nil
            }
        }
    }

    func runReducedPowerDirector() {
        directorTask?.cancel()

        phase = .scoreReveal
        pulse = false
        pulseLoopStarted = false
        starDrift = 0
        sceneGlow = 0.24
        cameraScale = 1.0
        cameraRotation = 0
        cameraTilt = 0
        shakeX = 0
        shakeY = 0
        warpOpacity = 0
        pressureOpacity = 0
        impactFlash = 0
        lensOpacity = 0
        shockwave = false
        heroVisible = true
        heroScale = 1.0
        heroLift = 0
        crownVisible = !heroShowsNoWinnerState
        crownScale = 1.0
        nameVisible = true
        scoreVisible = true
        allowContinue = false
        didContinue = false

        directorTask = Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                phase = .settled
                sceneGlow = 0.20
            }

            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    allowContinue = true
                }

                directorTask = nil
            }
        }
    }

    func startPulseLoopIfNeeded() {
        guard premiumMotionEnabled else { return }
        guard !pulseLoopStarted else { return }

        pulseLoopStarted = true
        pulse = false

        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

        func continueToHQ() {
            guard allowContinue, !didContinue else { return }

            didContinue = true
            allowContinue = false

            // HARD STOP all motion immediately
            directorTask?.cancel()
            directorTask = nil
            pulse = false

            SpatialAudioManager.shared.transition(to: .hq)
            onContinue()
        }
}

// MARK: - Helpers

private struct LensStreakView: View {
    let width: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(color)
                .frame(width: max(1, width * 1.75), height: 1.8)
                .blur(radius: 1.4)

            Circle()
                .fill(color)
                .frame(width: 118, height: 118)
                .blur(radius: 50)
        }
    }
}

private struct ShockwaveCircle: View {
    let active: Bool
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.78), lineWidth: 2.6)
                .scaleEffect(active ? 3.75 : 0.08)
                .opacity(active ? 0 : 1)

            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 1.2)
                .scaleEffect(active ? 4.20 : 0.10)
                .opacity(active ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.75), value: active)
    }
}

private struct ParticleField: View {
    let particles: [BackgroundStar]
    let accent: Color
    let pulse: Bool
    let intensity: Double

    var body: some View {
        ZStack {
            ForEach(particles, id: \.id) { star in
                Circle()
                    .fill(star.isAccent ? accent : Color.white)
                    .frame(width: star.size, height: star.size)
                    .offset(x: star.x, y: star.y)
                    .opacity(star.opacity * intensity)
                    .scaleEffect(pulse ? star.pulseScale : 1.0)
            }
        }
        .drawingGroup()
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                if newValue {
                    haptics.impactOccurred()
                }
            }
    }
}

private struct BackgroundStar {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
    let pulseScale: CGFloat
    let isAccent: Bool

    static let smallStars: [BackgroundStar] = [
        .init(id: 1, x: -176, y: -286, size: 1.4, opacity: 0.40, pulseScale: 1.10, isAccent: false),
        .init(id: 2, x: -126, y: -238, size: 1.2, opacity: 0.28, pulseScale: 1.08, isAccent: false),
        .init(id: 3, x: -58, y: -246, size: 1.7, opacity: 0.44, pulseScale: 1.06, isAccent: true),
        .init(id: 4, x: 18, y: -262, size: 1.3, opacity: 0.30, pulseScale: 1.05, isAccent: false),
        .init(id: 5, x: 92, y: -214, size: 1.5, opacity: 0.38, pulseScale: 1.08, isAccent: false),
        .init(id: 6, x: 176, y: -246, size: 1.1, opacity: 0.24, pulseScale: 1.04, isAccent: false),
        .init(id: 7, x: -198, y: -142, size: 1.1, opacity: 0.22, pulseScale: 1.04, isAccent: false),
        .init(id: 8, x: -138, y: -110, size: 1.6, opacity: 0.42, pulseScale: 1.08, isAccent: false),
        .init(id: 9, x: -72, y: -148, size: 1.2, opacity: 0.28, pulseScale: 1.04, isAccent: true),
        .init(id: 10, x: 10, y: -128, size: 1.4, opacity: 0.34, pulseScale: 1.06, isAccent: false),
        .init(id: 11, x: 88, y: -122, size: 1.4, opacity: 0.28, pulseScale: 1.05, isAccent: false),
        .init(id: 12, x: 182, y: -98, size: 1.1, opacity: 0.20, pulseScale: 1.03, isAccent: false),
        .init(id: 13, x: -188, y: -12, size: 1.3, opacity: 0.26, pulseScale: 1.05, isAccent: false),
        .init(id: 14, x: -116, y: 18, size: 1.7, opacity: 0.40, pulseScale: 1.08, isAccent: true),
        .init(id: 15, x: -30, y: 42, size: 1.3, opacity: 0.30, pulseScale: 1.05, isAccent: false),
        .init(id: 16, x: 46, y: 16, size: 1.1, opacity: 0.22, pulseScale: 1.04, isAccent: false),
        .init(id: 17, x: 122, y: 12, size: 1.5, opacity: 0.36, pulseScale: 1.08, isAccent: false),
        .init(id: 18, x: 190, y: 34, size: 1.1, opacity: 0.20, pulseScale: 1.03, isAccent: false),
        .init(id: 19, x: -186, y: 128, size: 1.4, opacity: 0.26, pulseScale: 1.05, isAccent: false),
        .init(id: 20, x: -110, y: 168, size: 1.6, opacity: 0.34, pulseScale: 1.08, isAccent: false),
        .init(id: 21, x: -42, y: 126, size: 1.2, opacity: 0.24, pulseScale: 1.04, isAccent: true),
        .init(id: 22, x: 26, y: 158, size: 1.4, opacity: 0.32, pulseScale: 1.06, isAccent: false),
        .init(id: 23, x: 98, y: 142, size: 1.3, opacity: 0.26, pulseScale: 1.05, isAccent: false),
        .init(id: 24, x: 182, y: 172, size: 1.1, opacity: 0.20, pulseScale: 1.03, isAccent: false)
    ]

    static let largeStars: [BackgroundStar] = [
        .init(id: 101, x: -152, y: -188, size: 2.5, opacity: 0.54, pulseScale: 1.12, isAccent: true),
        .init(id: 102, x: 148, y: -170, size: 2.1, opacity: 0.44, pulseScale: 1.10, isAccent: false),
        .init(id: 103, x: -180, y: 42, size: 2.0, opacity: 0.40, pulseScale: 1.08, isAccent: false),
        .init(id: 104, x: 168, y: 78, size: 2.3, opacity: 0.48, pulseScale: 1.10, isAccent: true),
        .init(id: 105, x: -18, y: -198, size: 2.0, opacity: 0.38, pulseScale: 1.07, isAccent: false),
        .init(id: 106, x: 18, y: 198, size: 2.2, opacity: 0.46, pulseScale: 1.09, isAccent: false),
        .init(id: 107, x: -86, y: 202, size: 2.4, opacity: 0.50, pulseScale: 1.11, isAccent: true),
        .init(id: 108, x: 90, y: -30, size: 2.0, opacity: 0.40, pulseScale: 1.08, isAccent: false)
    ]
}

private struct WarpLine {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let length: CGFloat
    let rotation: Double
    let opacity: Double

    static let lines: [WarpLine] = [
        .init(id: 1, x: -148, y: -124, width: 2.0, length: 122, rotation: -18, opacity: 0.72),
        .init(id: 2, x: -116, y: -30, width: 1.8, length: 104, rotation: -12, opacity: 0.64),
        .init(id: 3, x: -84, y: 82, width: 2.2, length: 134, rotation: -9, opacity: 0.76),
        .init(id: 4, x: -34, y: -148, width: 1.7, length: 90, rotation: -4, opacity: 0.56),
        .init(id: 5, x: -6, y: -24, width: 2.4, length: 146, rotation: 0, opacity: 0.82),
        .init(id: 6, x: 22, y: 98, width: 1.9, length: 114, rotation: 4, opacity: 0.60),
        .init(id: 7, x: 58, y: -124, width: 2.3, length: 138, rotation: 8, opacity: 0.74),
        .init(id: 8, x: 94, y: -12, width: 1.7, length: 94, rotation: 10, opacity: 0.52),
        .init(id: 9, x: 118, y: 98, width: 2.1, length: 128, rotation: 14, opacity: 0.70),
        .init(id: 10, x: 154, y: -84, width: 1.8, length: 108, rotation: 18, opacity: 0.58),
        .init(id: 11, x: -162, y: 22, width: 1.5, length: 84, rotation: -20, opacity: 0.46),
        .init(id: 12, x: 168, y: 30, width: 1.5, length: 82, rotation: 20, opacity: 0.46)
    ]
}
