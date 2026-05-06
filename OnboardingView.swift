//
//  OnboardingView.swift
//  TriviaGoatNextGen
//

import SwiftUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject private var app: AppState

    @State private var name: String = ""
    @State private var selectedTeam: TacticalTeam = .striker

    @State private var didTapEngage: Bool = false
    @State private var didTapRestore: Bool = false
    @State private var showOnboardingErrorAlert: Bool = false
    @State private var showHowItWorks: Bool = false

    @State private var mascotFloat: Bool = false
    @State private var heroGlow: Bool = false
    @State private var ringSpin: Bool = false

    @State private var invalidNameShakeTick: Int = 0
    @State private var fieldGlowPulse: Bool = false

    @State private var pendingWelcomeName: String = ""
    @State private var showWelcomeScreen: Bool = false
    @State private var hasTriggeredCompletion: Bool = false

    var body: some View {
        GeometryReader { geo in
            let appRef: AppState = app
            let safeTop = geo.safeAreaInsets.top
            let headerTopPadding = max(0, safeTop - 2)
            let headerBandHeight: CGFloat = 54
            let headerTotalHeight = headerTopPadding + headerBandHeight

            ZStack {
                SpaceBackground()
                backgroundAtmosphere

                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        OnboardingTopChrome(topPadding: headerTopPadding)

                        OnboardingHeaderBar()
                            .padding(.horizontal, 16)
                            .padding(.top, headerTopPadding + 2)
                    }
                    .frame(height: headerTotalHeight)
                    .zIndex(10)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            heroSection
                            setupCard(appRef: appRef)

                            if showHowItWorks {
                                howItWorksCard
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            Spacer(minLength: 32)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 0)
                        .padding(.bottom, 30)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .disabled(appRef.isBusy)
                }

                if appRef.isBusy {
                    deployOverlay
                        .transition(.opacity)
                        .zIndex(40)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .alert("onboarding.error.title".localized, isPresented: $showOnboardingErrorAlert) {
                Button("common.ok".localized, role: .cancel) {
                    app.onboardingErrorMessage = nil
                }
            } message: {
                Text(app.onboardingErrorMessage ?? "onboarding.error.try_different".localized)
            }
            .fullScreenCover(isPresented: $showWelcomeScreen) {
                WelcomeToTriviaGoatView(
                    playerName: pendingWelcomeName,
                    onStartDailyMission: routeToHQ,
                    onEnterTrainingArena: routeToHQ,
                    onGoToHQ: routeToHQ
                )
                .environmentObject(app)
            }
            .onAppear {
                didTapRestore = false
                SpatialAudioManager.shared.transition(to: .hq, force: true)
                startAmbientAnimations()
                prefillExistingCodenameIfNeeded()
            }
            .onChange(of: app.profile.displayName) { _, _ in
                prefillExistingCodenameIfNeeded()
            }
            .onChange(of: app.welcomeState) { _, newValue in
                guard let welcome = newValue else { return }
                guard !hasTriggeredCompletion else { return }

                hasTriggeredCompletion = true
                didTapEngage = false
                didTapRestore = false

                pendingWelcomeName = welcome.playerName

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard app.welcomeState != nil else { return }
                    showWelcomeScreen = true
                }
            }
            .onChange(of: app.onboardingErrorMessage) { _, newValue in
                let hasError = !(newValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ?? true)

                showOnboardingErrorAlert = hasError

                if hasError {
                    didTapEngage = false
                    didTapRestore = false
                    hasTriggeredCompletion = false
                }
            }
            .onChange(of: name) { _, newValue in
                let filtered = sanitizeCodenameInput(newValue)

                if filtered != newValue {
                    name = filtered
                    return
                }

                if app.onboardingErrorMessage != nil {
                    app.onboardingErrorMessage = nil
                }
            }
        }
    }

    private var backgroundAtmosphere: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.40),
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.90)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.orange.opacity(heroGlow ? 0.14 : 0.07),
                    Color.clear
                ],
                center: .top,
                startRadius: 10,
                endRadius: 320
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.blue.opacity(0.05),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 380
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)
            .opacity(0.35)
        }
        .allowsHitTesting(false)
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            mascotStage

            VStack(spacing: 6) {
                Text("onboarding.hero.eyebrow".localized)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.96))
                    .tracking(5.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Text("onboarding.hero.title".localized)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.98))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("onboarding.hero.subtitle".localized)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.95),
                            Color.orange.opacity(0.65)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 80, height: 4)
                .shadow(color: .orange.opacity(0.28), radius: 10, x: 0, y: 4)
                .padding(.top, 4)
        }
    }

    private var mascotStage: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(heroGlow ? 0.18 : 0.10))
                .frame(width: 160, height: 160)
                .blur(radius: 22)

            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                .frame(width: 132, height: 132)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.22),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 7])
                )
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(ringSpin ? 360 : 0))

            Group {
                if UIImage(named: "tg_mascot") != nil {
                    Image("tg_mascot")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 132)
                } else {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 104, height: 104)
                        .overlay(
                            Text("GT")
                                .font(.system(size: 30, weight: .black))
                                .foregroundColor(.orange)
                        )
                }
            }
            .offset(y: mascotFloat ? -4 : 4)
            .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 12)
        }
        .frame(height: 160)
    }

    private func setupCard(appRef: AppState) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader
            codenameBlock
            squadronBlock
            readinessBlock(appRef: appRef)
            engageButton(appRef: appRef)
            existingProfileButton(appRef: appRef)
            howItWorksToggle
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1.2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.orange.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.44), radius: 28, x: 0, y: 18)
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("onboarding.card.title".localized)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.90))
                    .tracking(2.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Spacer()

                Text("01 / 01")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.42))
                    .tracking(1.4)
                    .lineLimit(1)
            }

            Text("onboarding.card.subtitle".localized)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var codenameBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("onboarding.step.codename".localized)

            ZStack(alignment: .leading) {
                Text("onboarding.codename.placeholder".localized)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(name.isEmpty ? 0.40 : 0.12))
                    .padding(.horizontal, 16)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .allowsHitTesting(false)

                TextField("", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 16)
            }
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.075))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        cleanedName.isEmpty
                        ? Color.white.opacity(fieldGlowPulse ? 0.22 : 0.12)
                        : (isNameValid ? Color.orange.opacity(0.32) : Color.red.opacity(0.34)),
                        lineWidth: 1.4
                    )
                    .animation(.easeInOut(duration: 0.9), value: fieldGlowPulse)
            )
            .modifier(ShakeEffect(shakes: invalidNameShakeTick))

            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: nameInfoIcon)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(nameInfoColor)
                        .padding(.top, 1)

                    Text(nameSupportText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(nameInfoColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Text("\(cleanedName.count)/16")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.48))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if !isNameValid && !cleanedName.isEmpty {
                    Text("onboarding.codename.invalid_requirements".localized)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
        }
    }

    private var squadronBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("onboarding.step.squadron".localized)

            HStack(spacing: 10) {
                ForEach(TacticalTeam.allCases, id: \.self) { team in
                    squadronButton(for: team)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            Text(teamDescription(for: selectedTeam))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }

    private func squadronButton(for team: TacticalTeam) -> some View {
        let isSelected = team == selectedTeam

        return Button {
            SpatialAudioManager.shared.play(.uiTap)
            HapticManager.instance.impact(.light)

            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                selectedTeam = team
            }
        } label: {
            VStack(spacing: 6) {
                Text(team.label.uppercased())
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .allowsTightening(true)

                if isSelected {
                    Capsule()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: 18, height: 3)
                        .transition(.scale)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.10),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected ? .white.opacity(0.12) : .clear,
                radius: 10,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }

    private func readinessBlock(appRef: AppState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("onboarding.ready_check".localized)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    readinessChip(title: "onboarding.ready.codename".localized, isOn: isNameValid)
                    readinessChip(title: "onboarding.ready.squadron".localized, isOn: true)
                    readinessChip(title: "onboarding.ready.deploy".localized, isOn: isNameValid && !appRef.isBusy)
                }

                VStack(alignment: .leading, spacing: 10) {
                    readinessChip(title: "onboarding.ready.codename".localized, isOn: isNameValid)
                    readinessChip(title: "onboarding.ready.squadron".localized, isOn: true)
                    readinessChip(title: "onboarding.ready.deploy".localized, isOn: isNameValid && !appRef.isBusy)
                }
            }
        }
    }

    private func engageButton(appRef: AppState) -> some View {
        Button {
            engage(appRef: appRef)
        } label: {
            Text((didTapEngage || appRef.isBusy) ? "onboarding.deploying".localized : "onboarding.engage".localized)
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(
            ChunkyButtonStyle(
                color: (didTapEngage || appRef.isBusy)
                ? .orange.opacity(0.72)
                : (isNameValid ? .orange : .gray.opacity(0.35))
            )
        )
        .disabled(appRef.isBusy || didTapEngage || didTapRestore)
        .pressScale()
    }

    private func existingProfileButton(appRef: AppState) -> some View {
        Button {
            guard !didTapRestore else { return }

            didTapRestore = true
            didTapEngage = false
            hasTriggeredCompletion = false

            appRef.onboardingErrorMessage = nil

            HapticManager.instance.impact(.light)
            SpatialAudioManager.shared.play(.uiTap)

            appRef.secureOnboardingWithApple()
        } label: {
            VStack(spacing: 6) {
                Text("onboarding.secure.eyebrow".localized)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .tracking(1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 14, weight: .black))

                    Text("onboarding.secure.apple".localized)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                }
                .foregroundColor(.white.opacity(0.92))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(appRef.isBusy || didTapEngage)
        .pressScale()
    }

    private var howItWorksToggle: some View {
        Button {
            SpatialAudioManager.shared.play(.uiTap)
            HapticManager.instance.impact(.light)

            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                showHowItWorks.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: showHowItWorks ? "eye.slash.fill" : "info.circle.fill")
                    .font(.system(size: 14, weight: .black))

                Text(showHowItWorks ? "onboarding.how.hide".localized : "onboarding.how.show".localized)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundColor(.white.opacity(0.88))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundColor(.white.opacity(0.58))
            .tracking(2.6)
            .lineLimit(1)
            .minimumScaleFactor(0.70)
    }

    private func readinessChip(title: String, isOn: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? Color.green.opacity(0.95) : Color.white.opacity(0.18))
                .frame(width: 10, height: 10)

            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(isOn ? 0.92 : 0.46))
                .tracking(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .allowsTightening(true)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            Capsule()
                .fill(isOn ? Color.green.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            Capsule()
                .stroke(isOn ? Color.green.opacity(0.28) : Color.white.opacity(0.10), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: isOn)
    }

    private var nameInfoIcon: String {
        if cleanedName.isEmpty { return "info.circle.fill" }
        return isNameValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var nameInfoColor: Color {
        if cleanedName.isEmpty { return .white.opacity(0.58) }
        return isNameValid ? .green.opacity(0.92) : .orange.opacity(0.92)
    }

    private var nameSupportText: String {
        codenameValidationMessage
    }

    private func teamDescription(for team: TacticalTeam) -> String {
        switch team {
        case .striker:
            return "onboarding.team.striker.body".localized
        case .titan:
            return "onboarding.team.titan.body".localized
        case .phantom:
            return "onboarding.team.phantom.body".localized
        }
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("onboarding.how.title".localized)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2.2)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.orange.opacity(0.9))
            }

            howItWorksRow(step: "01", title: "onboarding.how.step1.title".localized, body: "onboarding.how.step1.body".localized)
            howItWorksRow(step: "02", title: "onboarding.how.step2.title".localized, body: "onboarding.how.step2.body".localized)
            howItWorksRow(step: "03", title: "onboarding.how.step3.title".localized, body: "onboarding.how.step3.body".localized)
            howItWorksRow(step: "04", title: "onboarding.how.step4.title".localized, body: "onboarding.how.step4.body".localized)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func howItWorksRow(step: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 58, height: 58)

                Text(step)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.orange.opacity(0.92))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(body)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var deployOverlay: some View {
        ZStack {
            Color.black
                .opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 140, height: 140)
                        .blur(radius: 20)

                    if UIImage(named: "tg_mascot") != nil {
                        Image("tg_mascot")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 110)
                            .shadow(color: .orange.opacity(0.28), radius: 18, x: 0, y: 10)
                    }
                }

                VStack(spacing: 6) {
                    Text(didTapRestore ? "onboarding.overlay.restoring".localized : "onboarding.overlay.deploying".localized)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.95))
                        .tracking(1.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Text(didTapRestore ? "onboarding.overlay.restoring_body".localized : "onboarding.overlay.deploying_body".localized)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ProgressView()
                    .tint(.orange)
                    .scaleEffect(1.1)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 20)
            .padding(.horizontal, 22)
        }
    }

    private var cleanedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var loweredName: String {
        cleanedName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private var compactName: String {
        loweredName.replacingOccurrences(of: "_", with: "")
    }

    private var isLengthValid: Bool {
        cleanedName.count >= 3 && cleanedName.count <= 16
    }

    private var hasOnlyAllowedCharacters: Bool {
        cleanedName.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil
    }

    private var hasEdgeUnderscore: Bool {
        cleanedName.hasPrefix("_") || cleanedName.hasSuffix("_")
    }

    private var hasDoubleUnderscore: Bool {
        cleanedName.contains("__")
    }

    private var reservedCodenames: Set<String> {
        [
            "admin", "administrator", "support", "staff", "system",
            "official", "mod", "moderator", "developer", "dev",
            "owner", "founder", "goat", "gt", "triviagoat",
            "trivia_goat", "firebase", "google", "openai"
        ]
    }

    private var isReservedName: Bool {
        reservedCodenames.contains(loweredName) || reservedCodenames.contains(compactName)
    }

    private var codenameValidationMessage: String {
        if cleanedName.isEmpty { return "onboarding.validation.enter".localized }
        if !isLengthValid { return "onboarding.validation.length".localized }
        if !hasOnlyAllowedCharacters { return "onboarding.validation.allowed".localized }
        if hasEdgeUnderscore { return "onboarding.validation.edge_underscore".localized }
        if hasDoubleUnderscore { return "onboarding.validation.double_underscore".localized }
        if isReservedName { return "onboarding.validation.reserved".localized }
        return "onboarding.validation.ready".localized
    }

    private var isNameValid: Bool {
        let upper = cleanedName.uppercased()

        return isLengthValid &&
        hasOnlyAllowedCharacters &&
        !hasEdgeUnderscore &&
        !hasDoubleUnderscore &&
        !isReservedName &&
        upper != "NEW PILOT"
    }

    private func sanitizeCodenameInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return String(filtered.prefix(16))
    }

    private func prefillExistingCodenameIfNeeded() {
        let existingName = app.profile.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let isPlaceholder = existingName.uppercased() == "NEW PILOT"

        guard name.isEmpty else { return }
        guard !existingName.isEmpty else { return }
        guard !isPlaceholder else { return }

        name = existingName
        pendingWelcomeName = existingName
    }

    private func engage(appRef: AppState) {
        guard !didTapEngage else { return }

        let n = cleanedName

        guard isNameValid else {
            HapticManager.instance.errorJolt()
            SpatialAudioManager.shared.play(.wrong)
            invalidNameShakeTick += 1
            return
        }

        pendingWelcomeName = n
        didTapEngage = true
        didTapRestore = false
        hasTriggeredCompletion = false
        app.onboardingErrorMessage = nil

        HapticManager.instance.successPulse()
        SpatialAudioManager.shared.play(.lockIn)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            appRef.completeOnboarding(name: n, team: selectedTeam)
        }
    }

    private func routeToHQ() {
        showWelcomeScreen = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeInOut(duration: 0.35)) {
                app.setRoute(.hq)
            }
        }
    }

    private func startAmbientAnimations() {
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            mascotFloat.toggle()
        }

        withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
            heroGlow.toggle()
        }

        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            ringSpin.toggle()
        }

        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            fieldGlowPulse.toggle()
        }
    }
}

// MARK: - Arena-style Top Chrome

private struct OnboardingTopChrome: View {
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

private struct OnboardingHeaderBar: View {
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("onboarding.header.title".localized)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.2)
                    .lineLimit(1)

                Text("onboarding.header.subtitle".localized)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(1.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)

                if UIImage(named: "tg_mascot") != nil {
                    Image("tg_mascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                } else {
                    Text("GT")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                }
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .tacticalPanel()
    }
}

// MARK: - Shake Effect

private struct ShakeEffect: GeometryEffect {
    var shakes: Int
    var animatableData: CGFloat

    init(shakes: Int) {
        self.shakes = shakes
        self.animatableData = CGFloat(shakes)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 6 * sin(animatableData * .pi * 2)
        return ProjectionTransform(
            CGAffineTransform(translationX: translation, y: 0)
        )
    }
}
