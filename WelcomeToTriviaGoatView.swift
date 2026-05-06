//
//  WelcomeToTriviaGoatView.swift
//  TriviaGoatNextGen
//

import SwiftUI
import UIKit

struct WelcomeToTriviaGoatView: View {

    @EnvironmentObject private var app: AppState

    let playerName: String?
    let onStartDailyMission: () -> Void
    let onEnterTrainingArena: () -> Void
    let onGoToHQ: () -> Void

    @State private var heroIn = false
    @State private var cardIn = false
    @State private var ctaIn = false
    @State private var hazeDrift = false
    @State private var pulse = false
    @State private var ringSpin: Double = 0
    @State private var sparkTick = 0
    @State private var didChooseAction = false
    @State private var didRunIntroSequence = false

    private var resolvedPlayerName: String {
        let cleaned = (playerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "welcome.rookie".localized : cleaned.uppercased()
    }

    var body: some View {
        GeometryReader { geo in
            let maxWidth = welcomeMaxWidth(for: geo.size.width)
            let horizontalPadding: CGFloat = geo.size.width >= 700 ? 28 : 18

            ZStack {
                welcomeBackground

                AmbientWelcomeHaze(drift: hazeDrift)
                    .opacity(0.22)
                    .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: geo.size.width >= 700 ? 18 : 16) {
                        heroSection
                            .padding(.top, max(22, geo.safeAreaInsets.top + 12))
                            .padding(.horizontal, horizontalPadding)
                            .opacity(heroIn ? 1 : 0)
                            .scaleEffect(heroIn ? 1.0 : 0.92)
                            .offset(y: heroIn ? 0 : 24)

                        contentCard
                            .padding(.horizontal, horizontalPadding)
                            .opacity(cardIn ? 1 : 0)
                            .scaleEffect(cardIn ? 1.0 : 0.97)
                            .offset(y: cardIn ? 0 : 18)

                        ctaStack
                            .padding(.horizontal, horizontalPadding)
                            .opacity(ctaIn ? 1 : 0)
                            .offset(y: ctaIn ? 0 : 14)
                    }
                    .frame(maxWidth: maxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, max(22, geo.safeAreaInsets.bottom + 18))
                }
                .allowsHitTesting(!didChooseAction)
                .opacity(didChooseAction ? 0.72 : 1.0)
            }
            .ignoresSafeArea()
        }
        .navigationBarHidden(true)
        .onAppear {
            guard !didRunIntroSequence else { return }
            didRunIntroSequence = true
            runIntro()
        }
    }

    private func welcomeMaxWidth(for width: CGFloat) -> CGFloat {
        width >= 900 ? 820 : (width >= 700 ? 760 : .infinity)
    }
}

// MARK: - UI

private extension WelcomeToTriviaGoatView {

    var welcomeBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.10, green: 0.07, blue: 0.03),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.orange.opacity(pulse ? 0.26 : 0.18),
                    Color.orange.opacity(0.08),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 440
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 340
            )
            .ignoresSafeArea()
        }
    }

    var heroSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.orange.opacity(0.42),
                                Color.orange.opacity(0.14),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 110
                        )
                    )
                    .frame(width: 190, height: 190)
                    .scaleEffect(pulse ? 1.04 : 0.96)

                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    .frame(width: 164, height: 164)
                    .rotationEffect(.degrees(ringSpin))

                Circle()
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1.5)
                    .frame(width: 146, height: 146)
                    .rotationEffect(.degrees(-ringSpin * 0.7))

                MascotHeroBadge(sparkTick: sparkTick)
                    .shadow(color: .orange.opacity(0.24), radius: 22, x: 0, y: 12)
            }

            VStack(spacing: 7) {
                Text("welcome.title".localized)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.60))
                    .tracking(2.2)

                Text("welcome.brand".localized)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.98),
                                Color.orange.opacity(0.92)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("welcome.subtitle".localized)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.50))
                    .tracking(1.5)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
    }

    var contentCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("welcome.you_are_in".localized(resolvedPlayerName))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.64)
                    .padding(.horizontal, 8)

                Text("welcome.hero.body".localized)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .padding(.horizontal, 8)
            }

            HStack(spacing: 10) {
                WelcomeStatChip(title: "welcome.card.play".localized, value: "welcome.card.fast".localized, symbol: "bolt.fill")
                WelcomeStatChip(title: "welcome.card.build".localized, value: "welcome.card.streaks".localized, symbol: "flame.fill")
                WelcomeStatChip(title: "welcome.card.climb".localized, value: "welcome.card.ranks".localized, symbol: "crown.fill")
            }

            VStack(spacing: 11) {
                WelcomePromptRow(symbol: "checkmark.seal.fill", text: "welcome.ready".localized)
                WelcomePromptRow(symbol: "sparkles", text: "welcome.first_run".localized)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.orange.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 24, x: 0, y: 18)
        .shadow(color: .orange.opacity(0.10), radius: 20, x: 0, y: 10)
    }

    var ctaStack: some View {
        VStack(spacing: 12) {
            Button {
                runAction(kind: .daily)
            } label: {
                Text("welcome.start_mission".localized)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .buttonStyle(ChunkyButtonStyle(color: .orange))
            .pressScale()

            Button {
                runAction(kind: .training)
            } label: {
                Text("welcome.training".localized)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(ChunkyButtonStyle(color: .white.opacity(0.30)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
            .pressScale()

            Button {
                runAction(kind: .hq)
            } label: {
                Text("welcome.hq".localized)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
            .pressScale()
        }
    }

    enum WelcomeActionKind {
        case daily
        case training
        case hq
    }

    func runAction(kind: WelcomeActionKind) {
        guard !didChooseAction else { return }
        didChooseAction = true

        switch kind {
        case .daily:
            HapticManager.instance.successPulse()
            SpatialAudioManager.shared.play(.lockIn)

        case .training:
            HapticManager.instance.impact(.medium)
            SpatialAudioManager.shared.play(.uiTap)

        case .hq:
            HapticManager.instance.impact(.light)
            SpatialAudioManager.shared.play(.uiTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            switch kind {
            case .daily:
                onStartDailyMission()
            case .training:
                onEnterTrainingArena()
            case .hq:
                onGoToHQ()
            }
        }
    }

    func runIntro() {
        SpatialAudioManager.shared.transition(to: .lobby, force: true)
        sparkTick += 1

        withAnimation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true)) {
            hazeDrift.toggle()
        }

        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulse.toggle()
        }

        withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
            ringSpin = 360
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
            heroIn = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.88)) {
                cardIn = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.90)) {
                ctaIn = true
            }
        }
    }
}

// MARK: - Mascot Hero

private struct MascotHeroBadge: View {
    let sparkTick: Int

    @State private var bob: Bool = false
    @State private var glow: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.12, blue: 0.08),
                            Color.black.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 118, height: 118)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            Circle()
                .stroke(Color.orange.opacity(glow ? 0.30 : 0.14), lineWidth: 2)
                .frame(width: 104, height: 104)
                .blur(radius: glow ? 0.2 : 0.0)

            VStack(spacing: 6) {
                Group {
                    if UIImage(named: "goat_icon") != nil {
                        Image("goat_icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else if UIImage(named: "tg_mascot") != nil {
                        Image("tg_mascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                    } else {
                        Text("GT")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.orange.opacity(0.95))
                            .frame(width: 72, height: 72)
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)

                Text("welcome.goat_mode".localized)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.62))
                    .tracking(1.35)
            }
            .offset(y: bob ? -2 : 2)

            WelcomeSparkField(active: sparkTick)
        }
        .frame(width: 118, height: 118)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                bob.toggle()
            }

            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow.toggle()
            }
        }
    }
}

private struct WelcomeSparkField: View {
    let active: Int

    @State private var animate: Bool = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                Circle()
                    .fill(i.isMultiple(of: 2) ? Color.orange.opacity(0.90) : Color.white.opacity(0.85))
                    .frame(width: sizes[i], height: sizes[i])
                    .blur(radius: 0.6)
                    .offset(
                        x: animate ? endX[i] : startX[i],
                        y: animate ? endY[i] : startY[i]
                    )
                    .opacity(animate ? 0.0 : 0.95)
            }
        }
        .onAppear {
            trigger()
        }
        .onChange(of: active) { _, _ in
            trigger()
        }
    }

    private let startX: [CGFloat] = [-8, 4, -18, 16, 0, -12, 14, -4, 20, -20]
    private let startY: [CGFloat] = [-8, -14, 4, 10, -22, 20, -6, 18, -18, 8]
    private let endX: [CGFloat] = [-34, 26, -46, 44, 0, -28, 32, -10, 50, -52]
    private let endY: [CGFloat] = [-40, -46, 18, 26, -58, 40, -20, 34, -38, 20]
    private let sizes: [CGFloat] = [5, 4, 4, 5, 6, 4, 5, 4, 4, 5]

    private func trigger() {
        animate = false
        withAnimation(.easeOut(duration: 0.75)) {
            animate = true
        }
    }
}

// MARK: - Supporting Views

private struct WelcomeStatChip: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .black))
                .foregroundColor(.orange.opacity(0.94))

            Text(title)
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.48))
                .tracking(1.1)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct WelcomePromptRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.orange.opacity(0.92))
                .frame(width: 18)

            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.80))
                .lineLimit(2)
                .minimumScaleFactor(0.84)

            Spacer()
        }
    }
}

private struct AmbientWelcomeHaze: View {
    let drift: Bool

    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.00),
                Color.white.opacity(0.04),
                Color.orange.opacity(0.02),
                Color.white.opacity(0.00)
            ],
            startPoint: drift ? .topLeading : .bottomTrailing,
            endPoint: drift ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
    }
}
