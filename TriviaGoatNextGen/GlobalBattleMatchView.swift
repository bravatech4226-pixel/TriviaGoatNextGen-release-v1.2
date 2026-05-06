//
// 🔒 GLOBAL BATTLE EXPERIENCE LOCK (DO NOT MODIFY LIGHTLY)
//
// This file controls the full live match experience including:
//
// - Pressure system (isPressureMoment, winningShot, tie-break escalation)
// - Presentation overlays (countdown, momentum, decisive moments)
// - Pre-reveal tension gating (critical to pacing)
// - Host-controlled reveal timing (DO NOT bypass)
// - Reveal impact spike (audio + haptic + pulse)
// - Finish cinematic trigger pipeline
//
// ⚠️ Any changes here can break gameplay feel instantly.
// ⚠️ Always test FULL match flow after edits:
//    - early rounds
//    - pressure buildup
//    - decisive moment
//    - reveal impact
//    - finish sequence
//
// This is a tuned system — not just UI.
//

import SwiftUI
import FirebaseAuth
import Combine
import UIKit
import SafariServices

struct GlobalBattleMatchView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var session: GlobalBattleSession

    @State private var pulseTick: Bool = false
    @State private var now: Date = Date()
    @State private var localQuestionStartAt: Date? = nil
    @State private var localQuestionKey: String = ""
    @State private var hostAutoRevealQuestion: Int? = nil
    @State private var hostAutoRevealQuestionKey: String = ""
    @State private var stagedChoiceIndex: Int? = nil
    @State private var sponsorURL: URL? = nil
    @State private var showSponsorSafari: Bool = false
    @State private var sponsorPlacement: SponsorPlacementPayload? = nil
    @State private var isLoadingSponsorPlacement: Bool = false
    @State private var showLeaveMatchAlert: Bool = false
    @State private var isViewActive: Bool = true

    @State private var showPresentationOverlay: Bool = false
    @State private var presentationMode: PresentationMode = .none
    @State private var presentationQuestionKey: String = ""
    @State private var countdownValue: Int = 3
    @State private var presentationTask: Task<Void, Never>? = nil
    @State private var lastDangerTriggerKey: String = ""
    @State private var showTieBreakDangerFlash: Bool = false

    @State private var experienceTask: Task<Void, Never>? = nil
    @State private var experiencePhase: MatchExperiencePhase = .live
    @State private var stagedFinishOutcome: GlobalBattleSession.FinishOutcome = .none
    @State private var finishFlightProgress: CGFloat = 0
    @State private var finishHeroScale: CGFloat = 1
    @State private var finishHeroGlow: Double = 0.22
    @State private var showFinishCrownBurst: Bool = false
    @State private var showVictoryCinematic: Bool = false
    @State private var showPreRevealTension: Bool = false
    @State private var lastPreRevealTensionKey: String = ""
    @State private var lastPressureAudioKey: String = ""
    @State private var lastCriticalAudioKey: String = ""
    @State private var didLaunchVictoryCinematic: Bool = false
    @State private var inputFrozenUntil: Date? = nil

    private let clock = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let minimumHostAutoRevealDelay: TimeInterval = 7.2

    private var finishBannerText: String {
        switch resolvedFinishOutcome {
        case .regulationWin:
            return "🏆 REGULATION WIN"
        case .tieBreakSpeedWin:
            return "⚡ TIE-BREAK SPEED WIN"
        case .winByDisqualification(_, _, let duringTieBreak):
            return duringTieBreak
                ? "⚠️ TIE-BREAK SURVIVAL WIN"
                : "⚠️ DISQUALIFICATION WIN"
        case .doubleDisqualification:
            return "💀 DOUBLE DISQUALIFICATION"
        case .none:
            return ""
        }
    }

    private var finishSubText: String {
        switch resolvedFinishOutcome {
        case .regulationWin(let winnerUID):
            return "\(session.displayName(for: winnerUID)) closes it out in regulation."

        case .tieBreakSpeedWin(let winnerUID):
            return "\(session.displayName(for: winnerUID)) answered fastest when it mattered most."

        case .winByDisqualification(let winnerUID, let disqualifiedUID, let duringTieBreak):
            let winnerName = session.displayName(for: winnerUID)
            let dqName = session.displayName(for: disqualifiedUID)

            return duringTieBreak
                ? "\(winnerName) survives the tie-break after \(dqName) is disqualified."
                : "\(winnerName) wins after \(dqName) is disqualified."

        case .doubleDisqualification:
            return "No pilot survived the final pressure sequence."

        case .none:
            guard let winnerUID = session.finishedWinnerUID else { return "" }
            return session.displayName(for: winnerUID)
        }
    }

    private enum PresentationMode: Equatable {
        case none
        case firstQuestionCountdown
        case momentumBreak
        case tieBreakAlert
        case finalApproach
        case decisiveMoment
    }
    
    private enum MatchExperiencePhase: Equatable {
        case live
        case finalQuestionHold
        case decisionPause
        case victorFlight
        case winnerReveal
    }
    
    
    
    
       var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            let horizontal: CGFloat = 14
            let topPadding = max(0, safeTop - 22)

            let sponsorVisible = shouldShowSponsorCard
            let sponsorHeight: CGFloat = sponsorVisible ? 118 : 0
            let sponsorBottomPadding: CGFloat = sponsorVisible ? max(10, safeBottom + 6) : 0

            let actionHeight: CGFloat = shouldShowActionDock ? 40 : 0
            let actionGapAboveSponsor: CGFloat = (sponsorVisible && shouldShowActionDock) ? 12 : 0
            let actionBottomPadding: CGFloat = sponsorVisible
                ? (sponsorHeight + sponsorBottomPadding + actionGapAboveSponsor)
                : (safeBottom + 12)

            let reservedBottom: CGFloat = {
                if showsWinnerSurface || showVictoryCinematic {
                    return safeBottom + 20
                }

                if sponsorVisible {
                    return actionHeight + actionBottomPadding + 14
                }

                return safeBottom + 18
            }()

            ZStack {
                SpaceBackground(motionMode: .staticPremium)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.clear,
                        Color.blue.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if pressureLevel > 0 && !showVictoryCinematic && !showPresentationOverlay {
                    inevitabilityWash
                        .transition(.opacity)
                        .zIndex(1)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 7) {
                        topBar
                        compactHeader

                        mainCard
                            .layoutPriority(2)

                        if showsWinnerSurface {
                            finishedShowcase
                                .layoutPriority(1)
                        } else {
                            standingsStrip
                                .layoutPriority(1)
                        }
                    }
                    .padding(.horizontal, horizontal)
                    .padding(.top, topPadding)
                    .padding(.bottom, reservedBottom)
                    .frame(width: geo.size.width, alignment: .top)
                }
                .clipped()
                .scaleEffect(pressureContentScale)
                .opacity(pressureContentOpacity)
                .animation(.easeInOut(duration: 0.45), value: pressureLevel)

                if !showsWinnerSurface && !showVictoryCinematic {
                    VStack {
                        Spacer()

                        if shouldShowActionDock {
                            actionDock(maxWidth: min(max(236, geo.size.width * 0.58), 272))
                                .padding(.bottom, actionBottomPadding)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontal)
                    .zIndex(20)
                }

                if sponsorVisible && !showVictoryCinematic {
                    VStack {
                        Spacer()

                        sponsorCard
                            .frame(maxWidth: .infinity)
                            .frame(height: sponsorHeight)
                            .padding(.horizontal, horizontal)
                            .padding(.bottom, sponsorBottomPadding)
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }

                if showTieBreakDangerFlash {
                    tieBreakDangerOverlay
                        .transition(.opacity)
                        .zIndex(98)
                }
                
                if showPreRevealTension {
                    preRevealTensionOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(96)
                }
                if showPresentationOverlay {
                    presentationOverlay
                        .transition(.opacity)
                        .zIndex(99)
                }

                if isEnteringFinishExperience {
                    finishExperienceOverlay
                        .transition(.opacity)
                        .zIndex(97)
                }
            }
        }
                          
        .navigationBarHidden(true)
        .sheet(isPresented: $showSponsorSafari, onDismiss: {
            sponsorURL = nil
        }) {
            if let sponsorURL {
                SafariSheet(url: sponsorURL)
            }
        }
        .fullScreenCover(isPresented: $showVictoryCinematic) {
            GlobalBattleVictoryCinematicView(
                winnerName: cinematicWinnerName,
                winnerScore: cinematicWinnerScore,
                finishOutcome: stagedFinishOutcome != .none ? stagedFinishOutcome : resolvedFinishOutcome
            ) {
                showVictoryCinematic = false
                app.exitGlobalBattleToHQ()
            }
        }
        .alert("global.match.leave.title".localized, isPresented: $showLeaveMatchAlert) {
            Button("global.match.leave.stay".localized, role: .cancel) { }

            Button("global.match.leave.confirm".localized, role: .destructive) {
                app.exitGlobalBattleToHQ()
            }
        } message: {
            Text("global.match.leave.body".localized)
        }
        .onAppear {
            guard app.canAccessGlobalBattle else {
                app.setRoute(.proPaywall)
                return
            }

            if didLaunchVictoryCinematic && showVictoryCinematic {
                return
            }
            
            isViewActive = true

            pulseTick = false
            syncQuestionTimingState()
            syncStagedChoice()
            loadSponsorPlacementIfNeeded()
            SpatialAudioManager.shared.transition(to: .matchCalm)
        }
        .onDisappear {
            if !showVictoryCinematic {
                isViewActive = false
                presentationTask?.cancel()
                presentationTask = nil
                experienceTask?.cancel()
                experienceTask = nil
                showPresentationOverlay = false
                experiencePhase = .live
                stagedFinishOutcome = .none
                finishFlightProgress = 0
                finishHeroScale = 1
                finishHeroGlow = 0.22
                showFinishCrownBurst = false
                sponsorURL = nil
                SpatialAudioManager.shared.transition(to: .hq)
            }
        }
        .onReceive(clock) { value in
            guard isViewActive else { return }

            now = value

            if session.roundPhase == .answering {
                applyPressureAudioState(reason: "clock")
                triggerLivePressureEscalation()
            }
            syncQuestionTimingState()
            syncStagedChoice()

            if pressureIsActiveNow || showPresentationOverlay || showPreRevealTension || isEnteringFinishExperience {
                withAnimation(.easeInOut(duration: 0.42)) {
                    pulseTick.toggle()
                }
            } else {
                pulseTick = false
            }

           
            hostRevealIfNeeded()
        }
        .onChange(of: session.phase) { _, newPhase in
            handleSessionPhaseChange(newPhase)
        }
        .onChange(of: session.runtime?.roundIndex) { _, _ in
            syncQuestionTimingState()
            syncStagedChoice()

            // 🔒 Reset all per-round experience + pressure latches
            experienceTask?.cancel()
            experienceTask = nil
            experiencePhase = .live
            stagedFinishOutcome = .none

            lastPressureAudioKey = ""
            lastCriticalAudioKey = ""
            lastDangerTriggerKey = ""
            lastPreRevealTensionKey = ""
            showTieBreakDangerFlash = false
            showPreRevealTension = false

            // 🔒 CRITICAL: reset cinematic latch ONLY when not finished
            if session.roundPhase != .finished && session.phase != .finished {
                didLaunchVictoryCinematic = false
            }
        }
        .onChange(of: session.liveQuestion?.key) { _, _ in
            syncQuestionTimingState()
            syncStagedChoice()
        }
        .onChange(of: session.roundPhase) { _, newPhase in
            syncQuestionTimingState()
            syncStagedChoice()
            triggerTieBreakDangerIfNeeded()

            if newPhase == .revealed || newPhase == .finished {
                presentationTask?.cancel()
                presentationTask = nil
                showPresentationOverlay = false
                presentationMode = .none
                showTieBreakDangerFlash = false
            }

            switch newPhase {
            case .waiting:
                applyPressureAudioState(reason: "waiting")

            case .answering:
                applyPressureAudioState(reason: "answering")

            case .revealed:
                SpatialAudioManager.shared.transition(to: .reveal)

                // 🔥 REVEAL IMPACT SPIKE
                HapticManager.instance.impact(.heavy)

                withAnimation(.easeOut(duration: 0.18)) {
                    pulseTick = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        pulseTick = false
                    }
                }

            case .finished:
                SpatialAudioManager.shared.transition(to: .reveal)
                if !didLaunchVictoryCinematic {
                    startFinishExperienceIfNeeded()
                }
            }
        }
        
        .onChange(of: showVictoryCinematic) { _, isShowing in
            if isShowing {
                presentationTask?.cancel()
                presentationTask = nil
                showPresentationOverlay = false
                presentationMode = .none
                showTieBreakDangerFlash = false
            }
        }
        
        .onChange(of: session.answers.count) { _, _ in
            syncStagedChoice()
            triggerTieBreakDangerIfNeeded()
            triggerPreRevealTensionIfNeeded()
        }
        .animation(.easeInOut(duration: 0.24), value: session.roundPhase)
        .animation(.easeInOut(duration: 0.24), value: session.runtime?.roundIndex)
        .animation(.easeInOut(duration: 0.24), value: showPresentationOverlay)
    }
}
// MARK: - Derived State

private extension GlobalBattleMatchView {
    
    func triggerLivePressureEscalation() {
        guard session.roundPhase == .answering else { return }
        guard !showPresentationOverlay else { return }
        guard !showPreRevealTension else { return }
        guard !activeQuestionKey.isEmpty else { return }

        // 🔥 only escalate in real pressure scenarios
        guard isPressureMoment || hasWinningShot || isTieBreakRound else { return }

        // 🔥 build pressure BEFORE final seconds
        let midPressureWindow = secondsRemaining <= 6 && secondsRemaining > 3
        let criticalWindow = secondsRemaining <= 3

        let key = "\(currentQuestionNumber)-\(activeQuestionKey)-live-pressure-\(secondsRemaining)"

        guard lastPressureAudioKey != key else { return }
        lastPressureAudioKey = key

        if criticalWindow {
            // 🚨 FULL PANIC MODE
            SpatialAudioManager.shared.transition(to: .matchPressure)
            SpatialAudioManager.shared.play(.dangerPulse)
            HapticManager.instance.impact(.heavy)

        } else if midPressureWindow {
            // ⚠️ BUILDING PRESSURE
            SpatialAudioManager.shared.transition(to: .matchPressure)
            HapticManager.instance.impact(.light)
        }
    }

    var myUID: String? {
        app.user?.uid ?? Auth.auth().currentUser?.uid
    }
    
    var pressureLevel: Int {
        if isCriticalAnsweringPhase { return 3 }
        if isLateAnsweringPhase { return 2 }
        if isPressureMoment || hasWinningShot || isTieBreakRound { return 2 }
        if isApproachingPressureMoment { return 1 }
        return 0
    }
    
    var pressureContentScale: CGFloat {
        switch pressureLevel {
        case 3: return 0.985
        case 2: return 0.992
        case 1: return 0.996
        default: return 1.0
        }
    }

    var pressureContentOpacity: Double {
        switch pressureLevel {
        case 3: return 0.96
        case 2: return 0.98
        default: return 1.0
        }
    }

    var inevitabilityWash: some View {
        ZStack {
            Color.black
                .opacity(pressureLevel == 3 ? 0.22 : 0.12)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    pressureBannerTint.opacity(pressureLevel == 3 ? 0.24 : 0.14),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)

            Rectangle()
                .strokeBorder(
                    pressureBannerTint.opacity(pulseTick ? 0.42 : 0.18),
                    lineWidth: pressureLevel == 3 ? 3 : 1.5
                )
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
    
    var resolvedFinishOutcome: GlobalBattleSession.FinishOutcome {
        if stagedFinishOutcome != .none {
            return stagedFinishOutcome
        }

        if session.finishOutcome != .none {
            return session.finishOutcome
        }

        guard let finish = session.runtime?.finish else {
            return .none
        }

        let type = finish.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch type {
        case "win_by_disqualification":
            if let winnerUID = finish.winnerUID,
               let disqualifiedUID = finish.disqualifiedUID {
                return .winByDisqualification(
                    winnerUID: winnerUID,
                    disqualifiedUID: disqualifiedUID,
                    duringTieBreak: finish.duringTieBreak
                )
            }

        case "double_disqualification":
            return .doubleDisqualification(
                disqualifiedUIDs: finish.disqualifiedUIDs,
                duringTieBreak: finish.duringTieBreak
            )

        case "tiebreak_speed_win":
            if let winnerUID = finish.winnerUID {
                return .tieBreakSpeedWin(winnerUID: winnerUID)
            }

        case "regulation_win":
            if let winnerUID = finish.winnerUID {
                return .regulationWin(winnerUID: winnerUID)
            }

        default:
            break
        }

        return .none
    }

    var myDisplayName: String {
        let cleaned = app.profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "PILOT" : cleaned
    }

    var iAmHost: Bool {
        session.isHost(currentUID: myUID)
    }

    var totalQuestions: Int {
        max(1, session.displayedQuestionCount)
    }

    var currentQuestionNumber: Int {
        max(1, session.runtime?.roundIndex ?? session.lobby?.roundIndex ?? 1)
    }

    var battleTopicText: String {
        let raw = session.lobby?.topic.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "GENERAL KNOWLEDGE" : raw.uppercased()
    }

    var sourceLabelText: String {
        session.activeQuestionSourceLabel.uppercased()
    }

    var isTieBreakRound: Bool {
        currentQuestionNumber > session.baseQuestionCount && !showsWinnerSurface
    }

    var isFinalRegulationRound: Bool {
        currentQuestionNumber == session.baseQuestionCount && !isTieBreakRound && !showsWinnerSurface
    }
    
    var myMissCount: Int {
        guard let uid = myUID else { return 0 }
        return session.missedAnswerStrikeCountForDisplay(uid: uid)
    }
    
    var opponentParticipant: GlobalBattleParticipant? {
        guard let myUID else { return nil }
        return sortedParticipants.first(where: { $0.uid != myUID })
    }

    var opponentMissCount: Int {
        guard let opponentUID = opponentParticipant?.uid else { return 0 }
        return session.missedAnswerStrikeCountForDisplay(uid: opponentUID)
    }

    var opponentDisplayNameShort: String {
        let raw = opponentParticipant?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "OPPONENT"
        return raw.isEmpty ? "OPPONENT" : raw.uppercased()
    }

    var endedOnTieBreak: Bool {
        switch resolvedFinishOutcome {
        case .tieBreakSpeedWin:
            return true
        case .winByDisqualification(_, _, let duringTieBreak):
            return duringTieBreak
        case .doubleDisqualification(_, let duringTieBreak):
            return duringTieBreak
        case .regulationWin, .none:
            return false
        }
    }

    var sortedParticipants: [GlobalBattleParticipant] {
        session.participants.sorted {
            if $0.score == $1.score {
                if $0.isHost != $1.isHost {
                    return $0.isHost && !$1.isHost
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.score > $1.score
        }
    }
    
    var projectedCorrectAnswerValue: Int {
        10
    }

    var winningShotParticipant: GlobalBattleParticipant? {
        guard !showsWinnerSurface else { return nil }
        guard session.roundPhase == .waiting || session.roundPhase == .answering else { return nil }

        if isTieBreakRound {
            return sortedParticipants.first
        }

        guard isFinalRegulationRound else { return nil }

        let players = sortedParticipants
        guard players.count >= 2 else { return nil }

        let leader = players[0]
        let runnerUp = players[1]

        if leader.score - runnerUp.score <= projectedCorrectAnswerValue {
            return leader
        }

        return nil
    }

    var hasWinningShot: Bool {
        winningShotParticipant != nil
    }

    var winningShotName: String {
        let raw = winningShotParticipant?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "PILOT"
        return raw.isEmpty ? "PILOT" : raw.uppercased()
    }

    var pressureIsActiveNow: Bool {
        isPressureMoment ||
        isApproachingPressureMoment ||
        hasWinningShot ||
        isLateAnsweringPhase ||
        isCriticalAnsweringPhase ||
        isTieBreakRound
    }

    var visibleStandingsParticipants: [GlobalBattleParticipant] {
        Array(sortedParticipants.prefix(10))
    }

    var leaderUID: String? {
        sortedParticipants.first?.uid
    }

    var atRiskUID: String? {
        if myMissCount >= 2 { return myUID }
        if opponentMissCount >= 2 { return opponentParticipant?.uid }
        return nil
    }
    
    var isPressureMoment: Bool {
        guard !showsWinnerSurface else { return false }

        switch session.roundPhase {
        case .waiting, .answering:
            break
        case .revealed, .finished:
            return false
        }

        let players = sortedParticipants
        guard players.count >= 2 else { return false }

        let leader = players[0]
        let runnerUp = players[1]
        let scoreGap = leader.score - runnerUp.score
        let withinStrikeRange = scoreGap <= projectedCorrectAnswerValue
        let isLateRegulation = !isTieBreakRound && currentQuestionNumber >= max(2, session.baseQuestionCount - 1)

        if isTieBreakRound {
            return true
        }

        if myMissCount >= 2 || opponentMissCount >= 2 {
            return true
        }

        if isFinalRegulationRound {
            return true
        }

        if isLateRegulation && withinStrikeRange {
            return true
        }

        return false
    }
    
    var isApproachingPressureMoment: Bool {
        guard !showsWinnerSurface else { return false }
        guard session.roundPhase == .waiting else { return false }
        guard !isTieBreakRound else { return false }

        let players = sortedParticipants
        guard players.count >= 2 else { return false }

        let leader = players[0]
        let runnerUp = players[1]
        let scoreGap = leader.score - runnerUp.score
        let oneQuestionSwing = 10
        let withinStrikeRange = scoreGap <= oneQuestionSwing

        return currentQuestionNumber == max(1, session.baseQuestionCount - 1) && withinStrikeRange
    }

    var standingsTitleText: String {
        sortedParticipants.count > 10 ? "LIVE TOP 10" : "LIVE STANDINGS"
    }
    
    var victor: GlobalBattleParticipant? {
        if let winnerUID = session.finishedWinnerUID {
            return session.participants.first(where: { $0.uid == winnerUID })
        }
        return sortedParticipants.first
    }

    var cinematicWinnerName: String {
        if case .doubleDisqualification = resolvedFinishOutcome {
            return "NO PILOT"
        }

        let raw = victor?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "PILOT"
        return raw.isEmpty ? "PILOT" : raw
    }

    var cinematicWinnerScore: Int {
        if case .doubleDisqualification = resolvedFinishOutcome {
            return 0
        }

        return victor?.score ?? 0
    }
    
    var pressureBanner: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle()
                    .fill(pressureBannerTint.opacity(0.18))
                    .frame(width: 34, height: 34)

                Image(systemName: pressureBannerIcon)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(pressureBannerTint.opacity(0.98))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(pressurePrimaryText)
                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white)
                    .tracking(1.05)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(pressureSecondaryText)
                    .font(DS.Typography.font(10, weight: .black, design: .rounded, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            if isCriticalAnsweringPhase {
                Text("\(secondsRemaining)S")
                    .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                    .foregroundColor(.red.opacity(0.98))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.red.opacity(0.16)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            pressureBannerTint.opacity(0.16),
                            Color.black.opacity(0.48),
                            pressureBannerTint.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(pressureBannerTint.opacity(pulseTick ? 0.82 : 0.38), lineWidth: 1.35)
        )
    }
    var pressurePrimaryText: String {
        if isCriticalAnsweringPhase {
            return hasWinningShot ? "FINAL SECONDS • WINNING SHOT LIVE" : "FINAL SECONDS • LOCK IT IN"
        }

        if isLateAnsweringPhase {
            return hasWinningShot ? "\(winningShotName) CAN END IT HERE" : "TIME IS RUNNING OUT"
        }

        if isTieBreakRound {
            return "FASTEST CORRECT ANSWER ENDS IT"
        }

        if isFinalRegulationRound {
            return "FINAL QUESTION • THIS CAN DECIDE THE BATTLE"
        }

        if hasWinningShot {
            if let myUID, winningShotParticipant?.uid == myUID {
                return "YOU HAVE THE WINNING SHOT"
            } else {
                return "\(winningShotName) HAS THE WINNING SHOT"
            }
        }

        if myMissCount >= 2 {
            return "ONE MISS AND YOU'RE DONE"
        }

        if opponentMissCount >= 2 {
            return "\(opponentDisplayNameShort) IS ONE MISS FROM ELIMINATION"
        }

        return "ONE QUESTION CAN FLIP THIS"
    }
    
    var preRevealPrimaryText: String {
        if isTieBreakRound {
            return "SPEED DECIDES NOW"
        }

        if isFinalRegulationRound {
            return "FINAL QUESTION"
        }

        if hasWinningShot {
            if let myUID, winningShotParticipant?.uid == myUID {
                return "YOU CAN END IT"
            } else {
                return "\(winningShotName) CAN END IT"
            }
        }

        return "THE WINDOW IS CLOSING"
    }

    var preRevealSecondaryText: String {
        if isTieBreakRound {
            return "Fastest correct answer takes the crown."
        }

        if isFinalRegulationRound {
            return "This one can decide the battle."
        }

        if hasWinningShot {
            if let myUID, winningShotParticipant?.uid == myUID {
                return "Your answer can finish the battle."
            } else {
                return "If they are right, this battle is over."
            }
        }

        return "Every lock matters now."
    }

    var pressureSecondaryText: String {
        if isCriticalAnsweringPhase {
            return "No hesitation now. Lock before the window closes."
        }

        if isLateAnsweringPhase {
            return "The clock is squeezing the field."
        }

        if isTieBreakRound {
            return "One clean tap. Speed decides the winner."
        }

        if isFinalRegulationRound {
            return "Final regulation question. Every lock matters."
        }

        if hasWinningShot {
            if let myUID, winningShotParticipant?.uid == myUID {
                return "This is your shot. Don’t hesitate."
            } else {
                return "If they get this right, it's over."
            }
        }

        if myMissCount >= 2 {
            return "You are one missed answer away from elimination."
        }

        if opponentMissCount >= 2 {
            return "They are hanging by a thread."
        }
       
        return "Momentum is close enough to swing."
    }

    var pressureBannerIcon: String {
        if isCriticalAnsweringPhase { return "timer.circle.fill" }
        if isTieBreakRound { return "bolt.fill" }
        if hasWinningShot { return "scope" }
        if myMissCount >= 2 || opponentMissCount >= 2 { return "exclamationmark.octagon.fill" }
        return "exclamationmark.triangle.fill"
    }

    var pressureBannerTint: Color {
        if isCriticalAnsweringPhase { return .red }
        if myMissCount >= 2 || opponentMissCount >= 2 { return .red }
        if isTieBreakRound { return .yellow }
        return .orange
    }

    var disqualifiedParticipants: [GlobalBattleParticipant] {
        let dqSet = Set(session.disqualifiedUIDs)
        return sortedParticipants.filter { dqSet.contains($0.uid) }
    }

    var fallenPilots: [GlobalBattleParticipant] {
        guard showsWinnerSurface else { return [] }

        switch resolvedFinishOutcome {
        case .doubleDisqualification:
            return sortedParticipants

        case .winByDisqualification(_, let disqualifiedUID, _):
            return sortedParticipants.filter { $0.uid == disqualifiedUID }

        case .regulationWin, .tieBreakSpeedWin, .none:
            guard let victor else { return [] }
            return sortedParticipants.filter { $0.uid != victor.uid }
        }
    }

    var isFinishedState: Bool {
        if case .finished = session.phase { return true }
        return session.roundPhase == .finished
    }

    var isEnteringFinishExperience: Bool {
        experiencePhase == .finalQuestionHold ||
        experiencePhase == .decisionPause ||
        experiencePhase == .victorFlight ||
        showVictoryCinematic
    }

    var showsWinnerSurface: Bool {
        experiencePhase == .winnerReveal
    }

    var shouldShowSponsorCard: Bool {
        guard sponsorPlacement != nil else { return false }
        guard !showsWinnerSurface else { return false }
        guard !isEnteringFinishExperience else { return false }
        guard !showVictoryCinematic else { return false }
        guard !isTieBreakRound else { return false }
        guard !showPresentationOverlay else { return false }

        switch session.roundPhase {
        case .waiting, .answering:
            return true
        case .revealed, .finished:
            return false
        }
    }

    var presentationTimeExtension: TimeInterval {
        guard showPresentationOverlay else { return 0 }

        switch presentationMode {
        case .firstQuestionCountdown:
            return 4.1
        case .momentumBreak:
            return 3.0
        case .tieBreakAlert:
            return 3.2
        case .finalApproach:
            return 3.65
        case .decisiveMoment:
            return 4.35
        case .none:
            return 0
        }
    }

    var effectiveDeadlineAt: Date? {
        let serverDeadline = session.deadlineAt?.addingTimeInterval(presentationTimeExtension)
        let localFallbackDeadline = localQuestionStartAt?
            .addingTimeInterval(TimeInterval(session.roundDurationSeconds) + presentationTimeExtension)

        switch (serverDeadline, localFallbackDeadline) {
        case let (server?, local?):
            return max(server, local)
        case let (server?, nil):
            return server
        case let (nil, local?):
            return local
        default:
            return nil
        }
    }

    var secondsRemaining: Int {
        guard session.roundPhase == .answering else { return 0 }
        guard let deadline = effectiveDeadlineAt else { return session.roundDurationSeconds }
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    var timeMetricText: String {
        guard session.roundPhase == .answering else { return "—" }

        if secondsRemaining <= 3 {
            return "⚠️ \(secondsRemaining)S"
        }

        return "\(secondsRemaining)S"
    }

    var localAnsweringElapsed: TimeInterval {
        guard session.roundPhase == .answering else { return 0 }
        guard let start = localQuestionStartAt else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    var activeQuestionKey: String {
        session.liveQuestion?.key ?? session.runtime?.question?.key ?? ""
    }

    var submittedChoiceIndex: Int? {
        session.submittedChoiceIndex(for: myUID)
    }

    var hasLockedAnswer: Bool {
        session.didSubmitAnswer(currentUID: myUID) || session.hasLockedAnswer
    }

    var displayChoiceIndex: Int? {
        submittedChoiceIndex ?? stagedChoiceIndex
    }

    var canLockAnswer: Bool {
        session.roundPhase == .answering &&
        !showPresentationOverlay &&
        !hasLockedAnswer &&
        stagedChoiceIndex != nil &&
        !isTieBreakRound &&
        now >= (inputFrozenUntil ?? .distantPast)
    }

    var canRevealCurrentQuestion: Bool {
        guard session.roundPhase == .answering else { return false }
        guard !activeQuestionKey.isEmpty else { return false }

        if session.submittedAnswerCount() >= max(1, session.playerCount) {
            return true
        }

        return secondsRemaining <= 0
    }

    var phaseLabel: String {
        if isFinishedState { return "FINISHED" }

        if showPresentationOverlay {
            return "READY"
        }

        switch session.roundPhase {
        case .waiting:
            return isTieBreakRound ? "TIEBREAK" : "STAGING"
        case .answering:
            return isTieBreakRound ? "TIEBREAK" : "LIVE"
        case .revealed:
            return "REVEAL"
        case .finished:
            return "FINISHED"
        }
    }

    var finishModeSubtitle: String {
        switch resolvedFinishOutcome {
        case .regulationWin:
            return "REGULATION DECIDED IT"
        case .tieBreakSpeedWin:
            return "SPEED DECIDED IT"
        case .winByDisqualification(_, _, let duringTieBreak):
            return duringTieBreak ? "SURVIVAL DECIDED IT" : "DISQUALIFICATION DECIDED IT"
        case .doubleDisqualification:
            return "NO PILOT SURVIVED"
        case .none:
            return endedOnTieBreak ? "SPEED DECIDED IT" : "REGULATION DECIDED IT"
        }
    }
    

    var cardEyebrowText: String {
        if isFinishedState {
            switch resolvedFinishOutcome {
            case .regulationWin:
                return "VICTOR LOCKED."
            case .tieBreakSpeedWin:
                return "FASTEST CORRECT WINS."
            case .winByDisqualification(_, _, let duringTieBreak):
                return duringTieBreak
                    ? "SURVIVAL DECIDES IT."
                    : "DISQUALIFICATION DECIDES IT."
            case .doubleDisqualification:
                return "NO PILOT SURVIVED THE TIE-BREAK."
            case .none:
                return endedOnTieBreak ? "FASTEST CORRECT WINS." : "VICTOR LOCKED."
            }
        }

        if showPresentationOverlay {
            switch presentationMode {
            case .firstQuestionCountdown:
                return "READY TO BATTLE."
            case .momentumBreak:
                return "MOMENTUM SHIFT."
            case .tieBreakAlert:
                return "TIE-BREAK LIVE."
            case .finalApproach:
                return "PRESSURE BUILDING."
            case .decisiveMoment:
                return "DECISIVE MOMENT."
            case .none:
                return "READY PILOTS."
            }
        }

        switch session.roundPhase {
        case .waiting:
            if isTieBreakRound { return "FASTEST CORRECT ANSWER WINS." }
            if isFinalRegulationRound { return "FINAL QUESTION IN PLAY." }
            return session.didLoadRemoteQuestions ? "QUESTION DECK READY." : "NEXT QUESTION INBOUND."
        case .answering:
            if isTieBreakRound {
                if hasLockedAnswer { return "ANSWER SENT — SPEED DECIDES." }
                return "MISS 3 TIE-BREAKS AND YOU'RE DISQUALIFIED."
            }
            if isFinalRegulationRound {
                if hasLockedAnswer { return "FINAL ANSWER LOCKED." }
                if stagedChoiceIndex != nil { return "FINAL CHOICE SELECTED." }
                return "FINAL QUESTION."
            }
            if hasLockedAnswer { return "ANSWER LOCKED." }
            if stagedChoiceIndex != nil { return "CHOICE SELECTED." }
            return "CHOOSE ONE ANSWER."
        case .revealed:
            return isTieBreakRound ? "SUDDEN-DEATH RESULT." : "ANSWER REVEALED."
        case .finished:
            return finishModeSubtitle + "."
        }
    }

    var questionPromptText: String {
        if showsWinnerSurface {
            switch resolvedFinishOutcome {
            case .doubleDisqualification:
                return "DOUBLE DISQUALIFICATION"

            case .winByDisqualification(_, _, let duringTieBreak):
                if duringTieBreak {
                    return "SURVIVAL VICTORY"
                }
                return victor?.displayName.uppercased() ?? "DISQUALIFICATION WIN"

            case .tieBreakSpeedWin:
                return victor?.displayName.uppercased() ?? "SPEED WIN"

            case .regulationWin:
                return victor?.displayName.uppercased() ?? "REGULATION WIN"

            case .none:
                return victor?.displayName.uppercased() ?? "BATTLE COMPLETE"
            }
        }

        if let prompt = session.liveQuestion?.prompt,
           !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return prompt
        }

        switch session.roundPhase {
        case .waiting:
            return iAmHost ? "Next question loading..." : "Stand by for the next question."
        case .answering:
            return "Waiting for live question..."
        case .revealed:
            return "Answer revealed."
        case .finished:
            return "Battle complete."
        }
    }

    var victorInitial: String {
        switch resolvedFinishOutcome {
        case .doubleDisqualification:
            return "DQ"
        default:
            let source = victor?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "V"
            return String(source.prefix(1)).uppercased()
        }
    }

    var winnerGlowOpacity: Double {
        pulseTick ? 0.30 : 0.18
    }
    var finishHeroLiveGlowOpacity: Double {
        if showFinishCrownBurst {
            return pulseTick ? 0.52 : 0.34
        }
        return max(winnerGlowOpacity, finishHeroGlow)
    }

    var finishFlightOffset: CGSize {
        let t = min(max(finishFlightProgress, 0), 1)

        let startX: CGFloat = -118
        let endX: CGFloat = 0
        let x = startX + ((endX - startX) * t)

        let arc = sin(t * .pi) * 78
        let y = -arc

        return CGSize(width: x, height: y)
    }

    var finishFlightRotation: Double {
        -18 + (Double(finishFlightProgress) * 28)
    }
    
    var winnerBannerSubtitle: String {
        switch resolvedFinishOutcome {
        case .regulationWin:
            if let victor {
                return "\(victor.score) PTS • WON IN REGULATION"
            }
            return "BATTLE COMPLETE"

        case .tieBreakSpeedWin:
            if let victor {
                return "\(victor.score) PTS • CROWNED ON SPEED"
            }
            return "BATTLE COMPLETE"

        case .winByDisqualification(_, let disqualifiedUID, let duringTieBreak):
            let dqName = session.displayName(for: disqualifiedUID)
            return duringTieBreak
                ? "\(dqName) missed 3 tie-break questions."
                : "\(dqName) hit the missed-answer disqualification limit."

        case .doubleDisqualification:
            return "Both pilots reached the disqualification limit."

        case .none:
            if let victor {
                return "\(victor.score) PTS • BATTLE COMPLETE"
            }
            return "BATTLE COMPLETE"
        }
    }
    var leaderCalloutName: String {
        guard let leader = sortedParticipants.first else { return "PILOT" }
        let cleaned = leader.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "PILOT" : cleaned.uppercased()
    }

    var leaderCalloutScore: Int {
        sortedParticipants.first?.score ?? 0
    }

    var topLeaders: [GlobalBattleParticipant] {
        guard let maxScore = sortedParticipants.map(\.score).max() else { return [] }
        return sortedParticipants.filter { $0.score == maxScore }
    }

    var hasTieForLead: Bool {
        topLeaders.count > 1
    }

    var pacingBreakRound: Bool {
        currentQuestionNumber > 1 &&
        !isTieBreakRound &&
        !isFinalRegulationRound &&
        ((currentQuestionNumber - 1) % 3 == 0)
    }

    var presentationTitleText: String {
        switch presentationMode {
        case .firstQuestionCountdown:
            return "GLOBAL BATTLE"
        case .momentumBreak:
            return "LIVE STANDINGS"
        case .tieBreakAlert:
            return "TIE-BREAKER"
        case .finalApproach:
            return "PRESSURE RISING"
        case .decisiveMoment:
            return "DECISIVE MOMENT"
        case .none:
            return "GLOBAL BATTLE"
        }
    }

    var presentationPrimaryText: String {
        switch presentationMode {
        case .firstQuestionCountdown:
            switch countdownValue {
            case 2:
                return "READY"
            case 1:
                return "SET"
            default:
                return "FIGHT!"
            }

        case .momentumBreak:
            if hasTieForLead {
                return "DEAD HEAT"
            }
            return "\(leaderCalloutName) LEADS"

        case .tieBreakAlert:
            return "FASTEST CORRECT ANSWER WINS"

        case .finalApproach:
            return "ONE QUESTION CAN FLIP THIS"

        case .decisiveMoment:
            if isFinalRegulationRound {
                return "FINAL QUESTION"
            }

            return hasWinningShot ? "\(winningShotName) HAS THE WINNING SHOT" : "THIS ONE DECIDES IT"

        case .none:
            return ""
        }
    }
    var presentationSecondaryText: String {
        switch presentationMode {
        case .firstQuestionCountdown:
            switch countdownValue {
            case 2:
                return "PILOTS TO START POSITIONS"
            case 1:
                return "QUESTION ONE IS COMING IN HOT"
            default:
                return "BATTLE LIVE"
            }

        case .momentumBreak:
            if hasTieForLead {
                return "TOP 10 SNAPSHOT • PRESSURE RISING"
            }
            return "\(leaderCalloutScore) PTS • TOP 10 SNAPSHOT"

        case .tieBreakAlert:
            return "MISS 3 TIE-BREAK QUESTIONS AND YOU'RE OUT"

        case .finalApproach:
            return "THE NEXT QUESTION CAN DECIDE THE BATTLE"

        case .decisiveMoment:
            if isFinalRegulationRound {
                if hasWinningShot {
                    return "\(winningShotName) CAN CLOSE IT OUT"
                }

                return "FINAL REGULATION QUESTION"
            }

            return hasWinningShot ? "WINNING SHOT IS LIVE" : "NEXT CORRECT ANSWER CAN END THE BATTLE"

        case .none:
            return ""
        }
    }

    var presentationTertiaryText: String {
        switch presentationMode {
        case .firstQuestionCountdown:
            return ""

        case .momentumBreak:
            if hasTieForLead {
                return "EVERY ANSWER COUNTS FROM HERE"
            }
            return "INTENTIONAL RESET • THEN BACK INTO THE FIGHT"

        case .tieBreakAlert:
            return "SPEED COUNTS NOW • TAP ONCE TO FIRE"

        case .finalApproach:
            return "THE WALL IS CLOSING IN"

        case .decisiveMoment:
            return "STAY SHARP • NO MISTAKES NOW"

        case .none:
            return ""
        }
    }

    var finishAccentText: String {
        switch resolvedFinishOutcome {
        case .regulationWin:
            if let victor {
                return "\(victor.displayName.uppercased()) SECURES THE WIN"
            }
            return "VICTORY CONFIRMED"

        case .tieBreakSpeedWin:
            if let victor {
                return "\(victor.displayName.uppercased()) WINS ON SPEED"
            }
            return "VICTORY CONFIRMED"

        case .winByDisqualification(_, let disqualifiedUID, let duringTieBreak):
            let dqName = session.displayName(for: disqualifiedUID).uppercased()
            if let victor {
                return duringTieBreak
                    ? "\(dqName) WAS DISQUALIFIED • \(victor.displayName.uppercased()) WINS BY SURVIVAL"
                    : "\(dqName) WAS DISQUALIFIED FOR MISSED ANSWERS • \(victor.displayName.uppercased()) WINS"
            }
            return duringTieBreak
                ? "\(dqName) WAS DISQUALIFIED"
                : "\(dqName) WAS DISQUALIFIED FOR MISSED ANSWERS"

        case .doubleDisqualification:
            return "BOTH PILOTS WERE DISQUALIFIED FOR FAILING TO ANSWER 3 TIE-BREAK QUESTIONS"

        case .none:
            if let victor {
                if endedOnTieBreak {
                    return "\(victor.displayName.uppercased()) WINS ON SPEED"
                }
                return "\(victor.displayName.uppercased()) SECURES THE WIN"
            }
            return "VICTORY CONFIRMED"
        }
    }

    var postMatchSummaryTitle: String {
        switch resolvedFinishOutcome {
        case .regulationWin, .tieBreakSpeedWin:
            if let victor {
                return "\(victor.displayName.uppercased()) CROWNED"
            }
            return "BATTLE COMPLETE"

        case .winByDisqualification:
            if let victor {
                return "\(victor.displayName.uppercased()) WINS"
            }
            return "BATTLE COMPLETE"

        case .doubleDisqualification:
            return "DOUBLE DISQUALIFICATION"

        case .none:
            if let victor {
                return "\(victor.displayName.uppercased()) WINS"
            }
            return "BATTLE COMPLETE"
        }
    }

    var postMatchSummarySubtitle: String {
        switch resolvedFinishOutcome {
        case .regulationWin:
            if let victor {
                return "\(victor.score) PTS • FINAL STANDINGS LOCKED IN REGULATION"
            }
            return "RETURN TO HQ"

        case .tieBreakSpeedWin:
            if let victor {
                return "\(victor.score) PTS • WON ON THE FASTEST CORRECT ANSWER"
            }
            return "RETURN TO HQ"

        case .winByDisqualification(_, let disqualifiedUID, let duringTieBreak):
            let dqName = session.displayName(for: disqualifiedUID)
            if let victor {
                return duringTieBreak
                    ? "\(dqName) was disqualified in tie-break • \(victor.displayName) wins by survival"
                    : "\(dqName) was disqualified for missed answers • \(victor.displayName) wins"
            }
            return duringTieBreak
                ? "\(dqName) was disqualified in tie-break"
                : "\(dqName) was disqualified for missed answers"

        case .doubleDisqualification:
            return "Both pilots were eliminated before a winner could be confirmed"

        case .none:
            if let victor {
                if endedOnTieBreak {
                    return "\(victor.score) PTS • WON ON THE FASTEST CORRECT ANSWER"
                }
                return "\(victor.score) PTS • FINAL STANDINGS LOCKED"
            }
            return "RETURN TO HQ"
        }
    }

    var heroShowsNoWinnerState: Bool {
        if case .doubleDisqualification = resolvedFinishOutcome { return true }
        return false
    }
    
    var isLateAnsweringPhase: Bool {
        session.roundPhase == .answering && secondsRemaining <= 5 && secondsRemaining > 3
    }

    var isCriticalAnsweringPhase: Bool {
        session.roundPhase == .answering && secondsRemaining <= 3
    }

    var shouldShowPressurePulse: Bool {
        session.roundPhase == .answering && pressureLevel > 0
    }

    var pressurePulseScale: CGFloat {
        switch pressureLevel {
        case 3: return pulseTick ? 1.02 : 0.985   // critical
        case 2: return pulseTick ? 1.015 : 0.99   // medium
        case 1: return pulseTick ? 1.008 : 0.995  // light
        default: return 1.0
        }
    }

    var tieBreakDangerKey: String {
        "\(activeQuestionKey)-\(myMissCount)-\(isTieBreakRound)"
    }

    var tieBreakWarningTitle: String {
        switch myMissCount {
        case 2:
            return "LAST CHANCE"
        default:
            return "WARNING"
        }
    }

    var tieBreakWarningColor: Color {
        switch myMissCount {
        case 2:
            return .red
        default:
            return .orange
        }
    }

    var tieBreakWarningBackground: Color {
        switch myMissCount {
        case 2:
            return Color.red.opacity(0.14)
        default:
            return Color.orange.opacity(0.12)
        }
    }

    var tieBreakWarningStroke: Color {
        switch myMissCount {
        case 2:
            return Color.red.opacity(pulseTick ? 0.92 : 0.62)
        default:
            return Color.orange.opacity(pulseTick ? 0.70 : 0.42)
        }
    }

    var tieBreakWarningIcon: String {
        switch myMissCount {
        case 2:
            return "exclamationmark.octagon.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }

    var finishPrimaryColor: Color {
        switch resolvedFinishOutcome {
        case .regulationWin:
            return .orange
        case .tieBreakSpeedWin:
            return .yellow
        case .winByDisqualification:
            return .orange
        case .doubleDisqualification:
            return .red
        case .none:
            return endedOnTieBreak ? .yellow : .orange
        }
    }

    var finishSecondaryColor: Color {
        switch resolvedFinishOutcome {
        case .regulationWin:
            return .orange.opacity(0.72)
        case .tieBreakSpeedWin:
            return .yellow.opacity(0.72)
        case .winByDisqualification:
            return .red.opacity(0.70)
        case .doubleDisqualification:
            return .red.opacity(0.72)
        case .none:
            return endedOnTieBreak ? .yellow.opacity(0.72) : .orange.opacity(0.72)
        }
    }

    var finishStrokeColor: Color {
        switch resolvedFinishOutcome {
        case .regulationWin:
            return Color.orange.opacity(0.30)
        case .tieBreakSpeedWin:
            return Color.yellow.opacity(0.30)
        case .winByDisqualification:
            return Color.red.opacity(0.24)
        case .doubleDisqualification:
            return Color.red.opacity(0.24)
        case .none:
            return endedOnTieBreak ? Color.yellow.opacity(0.30) : Color.orange.opacity(0.30)
        }
    }

    var finishHeroSymbolName: String {
        switch resolvedFinishOutcome {
        case .regulationWin:
            return "crown.fill"
        case .tieBreakSpeedWin:
            return "bolt.fill"
        case .winByDisqualification:
            return "shield.slash.fill"
        case .doubleDisqualification:
            return "xmark.octagon.fill"
        case .none:
            return endedOnTieBreak ? "bolt.fill" : "crown.fill"
        }
    }

    var finishHeroSymbolColor: Color {
        switch resolvedFinishOutcome {
        case .doubleDisqualification:
            return .white
        case .winByDisqualification:
            return .orange.opacity(0.98)
        case .tieBreakSpeedWin:
            return .yellow.opacity(0.98)
        case .regulationWin:
            return .yellow.opacity(0.98)
        case .none:
            return endedOnTieBreak ? .yellow.opacity(0.98) : .yellow.opacity(0.98)
        }
    }
}

// MARK: - Danger Overlay

private extension GlobalBattleMatchView {

    var tieBreakDangerOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.red.opacity(0.00),
                    Color.red.opacity(0.12),
                    Color.orange.opacity(0.10),
                    Color.red.opacity(0.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.92),
                            Color.orange.opacity(0.74),
                            Color.red.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: pulseTick ? 5 : 2.5
                )
                .ignoresSafeArea()
                .opacity(pulseTick ? 0.95 : 0.55)

            VStack {
                Spacer()

                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.red.opacity(0.98))

                    Text("LAST CHANCE")
                        .font(DS.Typography.font(14, weight: .black, design: .monospaced, cappedAt: 16))
                        .foregroundColor(.white.opacity(0.98))
                        .tracking(1.5)

                    Text("NEXT MISS = DISQUALIFICATION")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.red.opacity(0.92))
                        .tracking(1.1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.82))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.red.opacity(0.34), lineWidth: 1.2)
                )
                .padding(.bottom, 116)
            }
        }
        .allowsHitTesting(false)
    }
}

private extension GlobalBattleMatchView {

    var topBar: some View {
        HStack(spacing: 12) {
            if showsWinnerSurface {
                Button {
                    SpatialAudioManager.shared.play(isTieBreakRound ? .tieBreak : .uiTap)
                    app.exitGlobalBattleToHQ()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.orange.opacity(0.94))

                        Text("EXIT READY")
                            .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                            .foregroundColor(.white.opacity(0.84))
                            .tracking(1.0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .pressScale()
            } else {
                Button {
                    // 🔒 Block exit during finish experience
                    if isEnteringFinishExperience || showsWinnerSurface {
                        return
                    }

                    SpatialAudioManager.shared.play(.countdownTick)
                    showLeaveMatchAlert = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                        .foregroundColor(.white.opacity(0.90))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .pressScale()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("GLOBAL BATTLE")
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.orange.opacity(0.96))
                    .tracking(1.6)

                Text(showsWinnerSurface ? finishModeSubtitle : battleTopicText)
                    .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(.white.opacity(0.38))
                    .tracking(1.0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.orange.opacity(pulseTick ? 0.95 : 0.45))
                    .frame(width: 9, height: 9)

                Text(showsWinnerSurface ? "FINAL" : sourceLabelText)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.86))
                    .tracking(1.0)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }
    
    var sponsorDestinationHost: String {
        guard
            let raw = sponsorPlacement?.destinationURL,
            let url = URL(string: raw),
            let host = url.host,
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "OPEN LINK"
        }

        return host.uppercased()
    }

    var sponsorInitials: String {
        let raw = sponsorPlacement?.sponsorName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "SP"
        let parts = raw.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "SP" : letters
    }

    var sponsorFallbackBadge: some View {
        Text(sponsorInitials)
            .font(DS.Typography.font(18, weight: .black, design: .rounded, cappedAt: 22))
            .foregroundColor(.white)
    }

    @ViewBuilder
    func sponsorLogoView(
        image: Image,
        placement: SponsorPlacementPayload
    ) -> some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: 64, height: 64)

            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
    }
    

    var compactHeader: some View {
        HStack(spacing: 9) {
            compactMetric(title: "QUESTION", value: "\(currentQuestionNumber)/\(totalQuestions)")
            compactMetric(title: "PHASE", value: phaseLabel)
            compactMetric(title: "TIME", value: timeMetricText)
            compactMetric(
                title: "LOCKED",
                value: isFinishedState ? "—" : "\(session.submittedAnswerCount())"
            )
        }
    }

    func compactMetric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))
                .foregroundColor(.white.opacity(0.42))
                .tracking(1.0)

            Text(value)
                .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))
                .foregroundColor(
                    title == "TIME" && session.roundPhase == .answering
                        ? (
                            secondsRemaining <= 3
                            ? .red.opacity(0.98)
                            : (secondsRemaining <= 5
                                ? .orange.opacity(0.95)
                                : .white.opacity(0.96)
                              )
                          )
                        : .white.opacity(0.96)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    title == "TIME" && session.roundPhase == .answering && secondsRemaining <= 3
                        ? Color.red.opacity(pulseTick ? 0.72 : 0.38)
                        : Color.white.opacity(0.09),
                    lineWidth: title == "TIME" && session.roundPhase == .answering && secondsRemaining <= 3 ? 1.4 : 1
                )
        )
    }

    var mainCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(cardEyebrowText)
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(.orange.opacity(0.88))
                    .tracking(1.15)

                Spacer()

                if !showsWinnerSurface {
                    Text("\(session.playerCount) PILOTS")
                        .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))
                        .foregroundColor(.white.opacity(0.42))
                        .tracking(1.0)
                }
            }

            if showsWinnerSurface {
                winnerHeroCard
            } else {
                liveQuestionSurface
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(showsWinnerSurface ? Color.orange.opacity(0.30) : Color.white.opacity(0.10), lineWidth: 1.15)
        )
        
        .scaleEffect(pressurePulseScale)
        .animation(.easeInOut(duration: 0.5), value: pulseTick)
    }

    var liveQuestionSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                if pressureIsActiveNow {
                    pressureBanner
                }

                Text(questionPromptText)
                    .font(DS.Typography.font(20, weight: .black, design: .rounded, cappedAt: 24))
                    .foregroundColor(.white.opacity(0.97))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                topicPill(title: "TOPIC", value: battleTopicText)
                topicPill(title: "SOURCE", value: sourceLabelText)
            }

            if isTieBreakRound {
                VStack(spacing: 6) {
                    Text("⚡ TIE-BREAK")
                        .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.yellow)
                        .tracking(1.2)

                    tieBreakInstructionCard
                }
            }
            
            if isTieBreakRound && myMissCount > 0 {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(tieBreakWarningColor.opacity(0.18))
                            .frame(width: 28, height: 28)

                        Image(systemName: tieBreakWarningIcon)
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(tieBreakWarningColor.opacity(0.96))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(tieBreakWarningTitle)
                            .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                            .foregroundColor(tieBreakWarningColor.opacity(0.95))
                            .tracking(1.15)

                        Text(
                            myMissCount >= 2
                                ? "\(myMissCount)/3 MISSED • NEXT MISS = DISQUALIFICATION"
                                : "\(myMissCount)/3 MISSED • STAY SHARP"
                        )
                        .font(DS.Typography.font(11, weight: .black, design: .rounded, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.94))
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text("\(myMissCount)/3")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(tieBreakWarningColor.opacity(0.95))
                        .tracking(1.0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tieBreakWarningBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tieBreakWarningStroke, lineWidth: myMissCount >= 2 ? 1.5 : 1)
                )
                .scaleEffect(myMissCount >= 2 && pulseTick ? 1.01 : 1.0)
                .padding(.top, 4)
            }
            
            if isTieBreakRound && opponentMissCount > 0 {
                let opponentCritical = opponentMissCount >= 2

                HStack(spacing: 8) {
                    Image(systemName: opponentCritical ? "bolt.trianglebadge.exclamationmark.fill" : "eye.trianglebadge.exclamationmark")
                        .foregroundColor(
                            opponentCritical
                            ? .red.opacity(0.95)
                            : .orange.opacity(0.92)
                        )

                    Text(opponentCritical
                         ? "\(opponentDisplayNameShort) • LAST CHANCE • \(opponentMissCount)/3"
                         : "\(opponentDisplayNameShort) • \(opponentMissCount)/3 MISSED"
                    )
                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(
                        opponentCritical
                        ? .red.opacity(0.96)
                        : .orange.opacity(0.92)
                    )
                    .tracking(1.1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            opponentCritical
                            ? Color.red.opacity(0.14)
                            : Color.orange.opacity(0.10)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            opponentCritical
                            ? Color.red.opacity(0.34)
                            : Color.orange.opacity(0.26),
                            lineWidth: 1
                        )
                )
                .scaleEffect(opponentCritical && pulseTick ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.6), value: pulseTick)
            }

            if let question = session.liveQuestion {
                VStack(spacing: 9) {
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { idx, title in
                        answerRow(index: idx, title: title)
                    }
                }
            } else {
                waitingPayloadCard
            }
        }
    }

    func topicPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Typography.font(7, weight: .black, design: .monospaced, cappedAt: 9))
                .foregroundColor(.white.opacity(0.44))
                .tracking(1.0)

            Text(value)
                .font(DS.Typography.font(9, weight: .black, design: .rounded, cappedAt: 11))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    var tieBreakInstructionCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.orange.opacity(0.96))

            VStack(alignment: .leading, spacing: 3) {
                Text("TIE-BREAKER")
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(1.1)

                Text("Fastest correct answer wins. Miss 3 tie-break questions and you are disqualified.")
                    .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    var waitingPayloadCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.orange.opacity(0.85))
                .frame(width: 10, height: 10)

            Text(iAmHost ? "Preparing next question..." : "Waiting for next live question...")
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.65))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    func answerRow(index: Int, title: String) -> some View {
        let displayed = displayChoiceIndex == index
        let isLockedSubmission = submittedChoiceIndex == index
        let correctIndex = session.currentCorrectIndex
        let isCorrect = session.roundPhase == .revealed && correctIndex == index
        let isWrongLocked = session.roundPhase == .revealed && isLockedSubmission && correctIndex != index

        let bgColor: Color
        if displayed && session.roundPhase == .answering {
            bgColor = Color.orange.opacity(0.18)
        } else {
            bgColor = answerBackground(
                isDisplayed: displayed,
                isCorrect: isCorrect,
                isWrongLocked: isWrongLocked
            )
        }

        let strokeColor: Color
        if displayed && session.roundPhase == .answering {
            strokeColor = Color.orange.opacity(0.6)
        } else {
            strokeColor = answerStroke(
                isDisplayed: displayed,
                isCorrect: isCorrect,
                isWrongLocked: isWrongLocked
            )
        }

        let rowLineWidth: CGFloat = displayed ? 2 : 1.2
        let isDisabled = session.roundPhase != .answering || hasLockedAnswer || showPresentationOverlay

        return Button {
            guard session.roundPhase == .answering else { return }
            guard !hasLockedAnswer else { return }
            guard !showPresentationOverlay else { return }

            HapticManager.instance.impact(.light)

            if isTieBreakRound {
                withAnimation(.easeOut(duration: 0.15)) {
                    submitTieBreakChoice(index: index)
                }
            } else {
                stagedChoiceIndex = index
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            answerBadgeFill(
                                isDisplayed: displayed,
                                isCorrect: isCorrect,
                                isWrongLocked: isWrongLocked
                            )
                        )
                        .frame(width: 30, height: 30)

                    Text("\(index + 1)")
                        .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 14))
                        .foregroundColor(.white.opacity(0.96))
                }

                Text(title)
                    .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if session.roundPhase == .answering && displayed && !hasLockedAnswer && !showPresentationOverlay && !isTieBreakRound {
                    Text("SELECTED")
                        .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))
                        .foregroundColor(.white.opacity(0.72))
                        .tracking(1.0)
                }

                if session.roundPhase == .answering && isLockedSubmission {
                    Text(isTieBreakRound ? "SENT" : "LOCKED")
                        .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))
                        .foregroundColor(.orange.opacity(0.92))
                        .tracking(1.0)
                }

                if isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green.opacity(0.95))
                } else if isWrongLocked {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(0.95))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(strokeColor, lineWidth: rowLineWidth)
            )
        }
        .buttonStyle(.plain)
        .pressScale()
        .disabled(isDisabled)
    }

    func answerBadgeFill(isDisplayed: Bool, isCorrect: Bool, isWrongLocked: Bool) -> Color {
        if isCorrect { return .green.opacity(0.88) }
        if isWrongLocked { return .red.opacity(0.86) }
        if isDisplayed { return .white.opacity(0.24) }
        return .white.opacity(0.18)
    }

    func answerBackground(isDisplayed: Bool, isCorrect: Bool, isWrongLocked: Bool) -> Color {
        if isCorrect { return .green.opacity(0.18) }
        if isWrongLocked { return .red.opacity(0.14) }
        if isDisplayed { return .white.opacity(0.09) }
        return .white.opacity(0.05)
    }

    func answerStroke(isDisplayed: Bool, isCorrect: Bool, isWrongLocked: Bool) -> Color {
        if isCorrect { return .green.opacity(0.46) }
        if isWrongLocked { return .red.opacity(0.42) }
        if isDisplayed { return .white.opacity(0.18) }
        return .white.opacity(0.08)
    }
    
    func standingsRowBackground(for pilot: GlobalBattleParticipant) -> some View {
        let fill: Color

        if pilot.uid == leaderUID {
            fill = Color.orange.opacity(0.14)
        } else if pilot.uid == atRiskUID {
            fill = Color.red.opacity(0.12)
        } else {
            fill = Color.white.opacity(0.05)
        }

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(fill)
    }

    func standingsRowBorder(for pilot: GlobalBattleParticipant) -> some View {
        let stroke: Color

        if pilot.uid == leaderUID {
            stroke = Color.orange.opacity(0.24)
        } else if pilot.uid == atRiskUID {
            stroke = Color.red.opacity(0.26)
        } else {
            stroke = Color.white.opacity(0.08)
        }

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(stroke, lineWidth: 1)
    }

    func standingsRowScale(for pilot: GlobalBattleParticipant) -> CGFloat {
        guard pressureIsActiveNow else { return 1.0 }

        let shouldPulse = pilot.uid == leaderUID || pilot.uid == atRiskUID
        guard shouldPulse else { return 1.0 }

        return pulseTick ? 1.02 : 0.99
    }

    var standingsStrip: some View {
        VStack(spacing: 10) {
            HStack {
                Text(standingsTitleText)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.50))
                    .tracking(1.15)

                Spacer()

                if sortedParticipants.count > 10 {
                    Text("TOP 10")
                        .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))
                        .foregroundColor(.orange.opacity(0.88))
                        .tracking(1.0)
                }
            }

            VStack(spacing: 6) {
                ForEach(Array(visibleStandingsParticipants.enumerated()), id: \.element.uid) { idx, pilot in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(idx == 0 ? Color.orange.opacity(0.22) : Color.white.opacity(0.10))
                                .frame(width: 26, height: 26)

                            Text("\(idx + 1)")
                                .font(DS.Typography.font(10, weight: .black, design: .rounded, cappedAt: 12))
                                .foregroundColor(.white)
                        }

                        Text(pilot.displayName.uppercased())
                            .font(DS.Typography.font(11, weight: .black, design: .rounded, cappedAt: 14))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)

                        Spacer()

                        Text("\(pilot.score)")
                            .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                            .foregroundColor(idx == 0 ? .orange.opacity(0.95) : .white.opacity(0.75))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        standingsRowBackground(for: pilot)
                    )
                    .overlay(
                        standingsRowBorder(for: pilot)
                    )
                    .scaleEffect(standingsRowScale(for: pilot))
                    .animation(.easeInOut(duration: 0.5), value: pulseTick)
                }
            }

            if let myUID,
               let myIndex = sortedParticipants.firstIndex(where: { $0.uid == myUID }) {

                let myRank = myIndex + 1
                let me = sortedParticipants[myIndex]

                HStack {
                    Text("YOU")
                        .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))
                        .foregroundColor(.orange.opacity(0.9))

                    Text("#\(myRank)")
                        .font(DS.Typography.font(11, weight: .black, design: .rounded, cappedAt: 14))
                        .foregroundColor(.white)

                    Spacer()

                    Text("\(me.score) PTS")
                        .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.orange.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
            }

            if isTieBreakRound {
                Text("⚡ FASTEST CORRECT • MISS 3 = OUT")
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(.orange.opacity(0.9))
                    .tracking(1.0)
            }
        }
        .opacity(
            showPresentationOverlay
            ? 0
            : ((session.roundPhase == .answering || isEnteringFinishExperience) ? 0 : 1)
        )
        .scaleEffect(showPresentationOverlay ? 0.985 : 1.0)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.28), value: showPresentationOverlay)
        .animation(.easeInOut(duration: 0.28), value: session.roundPhase)
    }

    var winnerHeroCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .top) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                finishPrimaryColor.opacity(heroShowsNoWinnerState ? 0.94 : 0.99),
                                finishSecondaryColor,
                                Color.black.opacity(0.92)
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 74
                        )
                    )
                    .frame(width: 98, height: 98)
                    .overlay(
                        Circle()
                            .stroke(finishStrokeColor.opacity(0.95), lineWidth: 2)
                    )
                    .shadow(color: finishPrimaryColor.opacity(finishHeroLiveGlowOpacity), radius: 22)

                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .frame(width: 108, height: 108)

                if showFinishCrownBurst && !heroShowsNoWinnerState {
                    Circle()
                        .stroke(Color.yellow.opacity(pulseTick ? 0.92 : 0.42), lineWidth: pulseTick ? 3 : 1.4)
                        .frame(width: pulseTick ? 134 : 116, height: pulseTick ? 134 : 116)
                }

                if heroShowsNoWinnerState {
                    Image(systemName: finishHeroSymbolName)
                        .font(.system(size: 34, weight: .black))
                        .foregroundColor(finishHeroSymbolColor)
                        .offset(y: 22)
                } else {
                    Group {
                        if experiencePhase == .victorFlight {
                            Image(systemName: "sparkle")
                                .font(.system(size: 34, weight: .black))
                                .foregroundColor(.white.opacity(0.98))
                                .shadow(color: finishPrimaryColor.opacity(0.45), radius: 16)
                        } else {
                            Text(victorInitial)
                                .font(DS.Typography.font(31, weight: .black, design: .rounded, cappedAt: 37))
                                .foregroundColor(.white)
                        }
                    }
                }

                Capsule()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 48, height: 24)
                    .overlay(
                        Image(systemName: finishHeroSymbolName)
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(finishHeroSymbolColor)
                    )
                    .overlay(
                        Capsule()
                            .stroke(finishStrokeColor, lineWidth: 1)
                    )
                    .opacity(experiencePhase == .victorFlight ? 0.0 : 1.0)
                    .offset(y: -10)

                Image(systemName: heroShowsNoWinnerState ? "nosign" : finishHeroSymbolName)
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(finishPrimaryColor.opacity(0.88))
                    .opacity(experiencePhase == .victorFlight ? 0.0 : 1.0)
                    .offset(x: 38, y: -18)

                if showFinishCrownBurst && !heroShowsNoWinnerState {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.yellow.opacity(0.98))
                        .offset(y: -22)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 108, height: 112)
            .scaleEffect(experiencePhase == .victorFlight ? finishHeroScale : 1.0)
            .offset(experiencePhase == .victorFlight ? finishFlightOffset : .zero)
            .rotationEffect(.degrees(experiencePhase == .victorFlight ? finishFlightRotation : 0))
            .animation(.easeInOut(duration: 0.22), value: showFinishCrownBurst)

            VStack(alignment: .leading, spacing: 7) {
                Text(questionPromptText)
                    .font(DS.Typography.font(24, weight: .black, design: .rounded, cappedAt: 30))
                    .foregroundColor(.white.opacity(0.99))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !finishBannerText.isEmpty {
                    Text(finishBannerText)
                        .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.orange.opacity(0.92))
                        .tracking(1.1)
                }

                Text(winnerBannerSubtitle)
                    .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)

                if !finishSubText.isEmpty && !heroShowsNoWinnerState {
                    Text(finishSubText.uppercased())
                        .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(1.0)
                }

                HStack(spacing: 8) {
                    winnerStatPill(title: "LOCKED", value: "—")
                    winnerStatPill(title: "PILOTS", value: "\(session.playerCount)")
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            finishPrimaryColor.opacity(heroShowsNoWinnerState ? 0.08 : 0.12),
                            Color.black.opacity(0.88),
                            Color.black.opacity(0.97)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(finishStrokeColor, lineWidth: 1.5)
        )
        .shadow(color: finishPrimaryColor.opacity(finishHeroLiveGlowOpacity), radius: 28)
        .scaleEffect(showFinishCrownBurst ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.32), value: showFinishCrownBurst)
    }

    func winnerStatPill(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(DS.Typography.font(7, weight: .black, design: .monospaced, cappedAt: 9))
                .foregroundColor(.white.opacity(0.42))
                .tracking(1.0)

            Text(value)
                .font(DS.Typography.font(10, weight: .black, design: .rounded, cappedAt: 12))
                .foregroundColor(.white.opacity(0.94))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    var finishedShowcase: some View {
        VStack(spacing: 10) {
            finishRibbon
            fallenPilotsCard
            postMatchDecisionCard
        }
    }

    var finishRibbon: some View {
        HStack(spacing: 10) {
            Image(systemName: finishRibbonIconName)
                .foregroundColor(finishRibbonIconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(finishRibbonTitle)
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(finishPrimaryColor.opacity(0.95))
                    .tracking(1.1)

                Text(finishAccentText)
                    .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 14))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            if let victor, !heroShowsNoWinnerState {
                Text("\(victor.score) PTS")
                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(finishPrimaryColor.opacity(0.96))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(finishPrimaryColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(finishStrokeColor.opacity(0.82), lineWidth: 1)
        )
    }

    var finishRibbonIconName: String {
        switch resolvedFinishOutcome {
        case .regulationWin:
            return "crown.fill"
        case .tieBreakSpeedWin:
            return "bolt.fill"
        case .winByDisqualification:
            return "shield.slash.fill"
        case .doubleDisqualification:
            return "xmark.octagon.fill"
        case .none:
            return endedOnTieBreak ? "bolt.fill" : "crown.fill"
        }
    }

    var finishRibbonIconColor: Color {
        switch resolvedFinishOutcome {
        case .regulationWin:
            return .yellow.opacity(0.98)
        case .tieBreakSpeedWin:
            return .yellow.opacity(0.98)
        case .winByDisqualification:
            return .orange.opacity(0.98)
        case .doubleDisqualification:
            return .red.opacity(0.98)
        case .none:
            return endedOnTieBreak ? .yellow.opacity(0.98) : .yellow.opacity(0.98)
        }
    }

    var finishRibbonTitle: String {
        switch resolvedFinishOutcome {
        case .regulationWin:
            return "BATTLE COMPLETE"
        case .tieBreakSpeedWin:
            return "TIE-BREAK COMPLETE"
        case .winByDisqualification:
            return "DISQUALIFICATION COMPLETE"
        case .doubleDisqualification:
            return "DOUBLE DISQUALIFICATION"
        case .none:
            return endedOnTieBreak ? "TIE-BREAK COMPLETE" : "BATTLE COMPLETE"
        }
    }

    var fallenPilotsCard: some View {
        let winnerName = victor?.displayName.uppercased() ?? "PILOT"
        let winnerScore = victor?.score ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            Text(session.isDoubleDisqualificationFinish ? "FINAL OUTCOME" : "FINAL STANDINGS")
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.50))
                .tracking(1.1)

            VStack(spacing: 9) {
                if victor != nil && !session.isDoubleDisqualificationFinish {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.orange.opacity(0.22))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: session.endedByTieBreakSpeed ? "bolt.fill" : (session.endedByDisqualification ? "shield.fill" : "crown.fill"))
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.yellow.opacity(0.98))
                            )

                        Text(winnerName)
                            .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))
                            .foregroundColor(.white.opacity(0.98))
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer()

                        Text("\(winnerScore) PTS")
                            .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                            .foregroundColor(.orange.opacity(0.96))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.orange.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.orange.opacity(0.20), lineWidth: 1)
                    )
                }

                switch resolvedFinishOutcome {
                case .winByDisqualification(_, let disqualifiedUID, _):
                    if let dqPilot = session.participants.first(where: { $0.uid == disqualifiedUID }) {
                        fallenPilotRow(dqPilot, badge: "DISQUALIFIED")
                    }

                case .doubleDisqualification:
                    ForEach(disqualifiedParticipants, id: \.uid) { pilot in
                        fallenPilotRow(pilot, badge: "DISQUALIFIED")
                    }

                case .regulationWin, .tieBreakSpeedWin, .none:
                    ForEach(fallenPilots, id: \.uid) { pilot in
                        fallenPilotRow(pilot, badge: nil)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.80),
                            Color.black.opacity(0.72),
                            Color.blue.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    func fallenPilotRow(_ pilot: GlobalBattleParticipant, badge: String?) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill((badge == nil ? Color.white.opacity(0.14) : Color.red.opacity(0.20)))
                .frame(width: 26, height: 26)
                .overlay(
                    Group {
                        if badge != nil {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.red.opacity(0.92))
                        }
                    }
                )

            Text(pilot.displayName.uppercased())
                .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let badge {
                Text(badge)
                    .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))
                    .foregroundColor(.red.opacity(0.90))
                    .tracking(0.9)
                    .lineLimit(1)
            }

            Text("\(pilot.score) PTS")
                .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                .foregroundColor(.orange.opacity(0.88))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    var postMatchDecisionCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered.2.crossed")
                    .foregroundColor(finishPrimaryColor.opacity(0.96))

                VStack(alignment: .leading, spacing: 2) {
                    Text("GLOBAL BATTLE COMPLETE")
                        .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                        .foregroundColor(finishPrimaryColor.opacity(0.95))
                        .tracking(1.1)

                    Text(postMatchSummaryTitle)
                        .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 17))
                        .foregroundColor(.white.opacity(0.96))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(postMatchSummarySubtitle)
                        .font(DS.Typography.font(10, weight: .semibold, design: .rounded, cappedAt: 12))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }

                Spacer()
            }

            Button {
                HapticManager.instance.impact(.light)
                app.exitGlobalBattleToHQ()
            } label: {
                Text("BACK TO HQ")
                    .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(ChunkyButtonStyle(color: .orange))
            .pressScale()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            finishPrimaryColor.opacity(0.12),
                            Color.black.opacity(0.90),
                            Color.black.opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(finishStrokeColor.opacity(0.82), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.30), radius: 16, y: 6)
    }

    func actionDock(maxWidth: CGFloat) -> some View {
        actionArea(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    var shouldShowActionDock: Bool {
        if isEnteringFinishExperience || showsWinnerSurface {
            return false
        }

        if isTieBreakRound {
            return session.roundPhase == .answering && hasLockedAnswer
        }

        switch session.roundPhase {
        case .answering:
            return hasLockedAnswer || stagedChoiceIndex != nil
        case .revealed, .finished:
            return false
        default:
            return false
        }
    }

    @ViewBuilder
    func actionArea(maxWidth: CGFloat) -> some View {
        switch session.roundPhase {
        case .answering:
            if hasLockedAnswer {
                lockedStateBar(maxWidth: maxWidth)
            } else if stagedChoiceIndex != nil && !isTieBreakRound {
                primaryButton(
                    title: "LOCK IN",
                    enabled: canLockAnswer,
                    maxWidth: maxWidth
                ) {
                    lockStagedChoice()
                }
            } else {
                Color.clear.frame(height: 0)
            }

        case .revealed, .finished:
            Color.clear.frame(height: 0)

        default:
            Color.clear.frame(height: 0)
        }
    }

    func lockedStateBar(maxWidth: CGFloat) -> some View {
        let remaining = max(0, session.playerCount - session.submittedAnswerCount())

        let lockText = isTieBreakRound
            ? "⚡ SENT — SPEED DECIDES"
            : (remaining > 0
                ? "🔒 LOCKED — \(remaining) STILL ANSWERING"
                : "🔒 ALL ANSWERS LOCKED")

        return HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundColor(.orange.opacity(0.94))

            Text(lockText)
                .font(DS.Typography.font(13, weight: .black, design: .rounded, cappedAt: 16))
                .foregroundColor(.white.opacity(0.92))

            Spacer()

            if session.roundPhase == .answering {
                HStack(spacing: 8) {
                    Text("\(secondsRemaining)S")

                    if remaining > 0 {
                        Circle()
                            .fill(
                                secondsRemaining <= 3
                                    ? Color.red.opacity(pulseTick ? 1 : 0.45)
                                    : Color.orange.opacity(pulseTick ? 1 : 0.4)
                            )
                            .frame(width: 6, height: 6)
                    }
                }
                .font(DS.Typography.font(13, weight: .black, design: .rounded, cappedAt: 16))
                .foregroundColor(
                    secondsRemaining <= 3
                        ? .red.opacity(0.95)
                        : .orange.opacity(0.95)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: maxWidth)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    secondsRemaining <= 3
                        ? Color.red.opacity(pulseTick ? 0.58 : 0.28)
                        : Color.orange.opacity(0.18),
                    lineWidth: secondsRemaining <= 3 ? 1.3 : 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    var preRevealTensionOverlay: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    pressureBannerTint.opacity(0.28),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)

            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    pressureBannerTint.opacity(pulseTick ? 0.88 : 0.34),
                    lineWidth: pulseTick ? 4 : 1.8
                )
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("DECISIVE QUESTION")
                    .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                    .foregroundColor(pressureBannerTint.opacity(0.98))
                    .tracking(2.0)

                Text(preRevealPrimaryText)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .shadow(color: pressureBannerTint.opacity(0.42), radius: 18)

                Text(preRevealSecondaryText)
                    .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                    .foregroundColor(.white.opacity(0.66))
                    .tracking(1.1)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .scaleEffect(pulseTick ? 1.025 : 0.98)
            .animation(.easeInOut(duration: 0.45), value: pulseTick)
        }
        .allowsHitTesting(false)
    }

    var finishExperienceOverlay: some View {
        ZStack {
            Color.black.opacity(experiencePhase == .finalQuestionHold ? 0.18 : 0.84)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                switch experiencePhase {
                case .finalQuestionHold:
                    VStack(spacing: 12) {
                        Text("BATTLE CONTROL")
                            .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                            .foregroundColor(.orange.opacity(0.96))
                            .tracking(1.7)

                        Text("Holding for verdict…")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.97))
                            .multilineTextAlignment(.center)
                    }

                case .decisionPause:
                    VStack(spacing: 12) {
                        Text("VERDICT")
                            .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                            .foregroundColor(.orange.opacity(0.96))
                            .tracking(1.7)

                        Text(finishBannerText.isEmpty ? "RESULT CONFIRMED" : finishBannerText)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.98))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if !finishSubText.isEmpty {
                            Text(finishSubText)
                                .font(DS.Typography.font(13, weight: .black, design: .rounded, cappedAt: 15))
                                .foregroundColor(.white.opacity(0.72))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                    }

                case .victorFlight:
                    VStack(spacing: 12) {
                        Text("RETURN TO BASE")
                            .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                            .foregroundColor(.orange.opacity(0.96))
                            .tracking(1.7)

                        Text("Champion inbound…")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.98))
                            .multilineTextAlignment(.center)

                        Text("MILKY WAY PASS • HOME BASE LOCK")
                            .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                            .foregroundColor(.white.opacity(0.50))
                            .tracking(1.1)
                    }

                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
    }

    var presentationOverlay: some View {
        ZStack {
            Color.black.opacity(0.90)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(presentationTitleText)
                    .font(DS.Typography.font(12, weight: .black, design: .monospaced, cappedAt: 14))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.8)

                Text(presentationPrimaryText)
                    .font(
                        .system(
                            size: (presentationMode == .firstQuestionCountdown) ? 78 : 34,
                            weight: .black,
                            design: .rounded
                        )
                    )
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: Color.orange.opacity(0.35), radius: 18)
                    .scaleEffect(
                        presentationMode == .firstQuestionCountdown
                        ? (countdownValue == 0 ? 1.03 : 0.94)
                            : (pulseTick ? 1.035 : 0.97)
                    )
                    .opacity(
                        presentationMode == .firstQuestionCountdown
                            ? (countdownValue == 0 ? 1.0 : 0.96)
                            : 1.0
                    )
                    .animation(.spring(response: 0.38, dampingFraction: 0.74), value: countdownValue)
                    .padding(.horizontal, 20)
                Text(presentationSecondaryText)
                    .font(DS.Typography.font(13, weight: .black, design: .monospaced, cappedAt: 15))
                    .foregroundColor(.white.opacity(0.78))
                    .tracking(1.35)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                if presentationMode == .momentumBreak {
                    VStack(spacing: 8) {
                        ForEach(Array(visibleStandingsParticipants.enumerated()), id: \.element.uid) { idx, pilot in
                            HStack(spacing: 10) {
                                Text("#\(idx + 1)")
                                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                                    .foregroundColor(idx == 0 ? .orange.opacity(0.96) : .white.opacity(0.70))
                                    .frame(width: 28, alignment: .leading)

                                Text(pilot.displayName.uppercased())
                                    .font(DS.Typography.font(11, weight: .black, design: .rounded, cappedAt: 13))
                                    .foregroundColor(.white.opacity(0.94))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(pilot.score)")
                                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                                    .foregroundColor(idx == 0 ? .orange.opacity(0.96) : .white.opacity(0.78))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                } else {
                    Text(presentationTertiaryText)
                        .font(DS.Typography.font(10, weight: .semibold, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.white.opacity(0.46))
                        .tracking(1.05)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    func primaryButton(title: String, enabled: Bool, maxWidth: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.instance.impact(.light)
            action()
        }) {
            Text(title)
                .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
        }
        .buttonStyle(ChunkyButtonStyle(color: .orange))
        .pressScale()
        .disabled(!enabled)
        .frame(maxWidth: maxWidth)
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
    }

    var sponsorCard: some View {
        Group {
            if let placement = sponsorPlacement {
                Button {
                    openSponsorLink()
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("SPONSORED")
                                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                                    .foregroundColor(.orange.opacity(0.96))
                                    .tracking(1.2)

                                Text(placement.sponsorName.uppercased())
                                    .font(DS.Typography.font(7, weight: .black, design: .monospaced, cappedAt: 9))
                                    .foregroundColor(.white.opacity(0.58))
                                    .tracking(0.9)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.72)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Text(placement.headline)
                                .font(DS.Typography.font(15, weight: .black, design: .rounded, cappedAt: 19))
                                .foregroundColor(.white.opacity(0.995))
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                                .fixedSize(horizontal: false, vertical: true)
                                .shadow(color: Color.white.opacity(0.08), radius: 4)

                            if let subheadline = placement.subheadline,
                               !subheadline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(subheadline)
                                    .font(DS.Typography.font(10, weight: .semibold, design: .rounded, cappedAt: 12))
                                    .foregroundColor(.white.opacity(0.86))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: 8) {
                                adInfoPill("CTA", (placement.ctaLabel ?? "Learn More").uppercased())
                                adInfoPill("SLOT", (placement.slotKey ?? "GLOBAL").uppercased())
                            }

                            Text(sponsorDestinationHost)
                                .font(DS.Typography.font(9, weight: .semibold, design: .rounded, cappedAt: 11))
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.orange.opacity(0.98),
                                                Color.orange.opacity(0.68),
                                                Color.black.opacity(0.90)
                                            ],
                                            center: .center,
                                            startRadius: 6,
                                            endRadius: 44
                                        )
                                    )
                                    .frame(width: 72, height: 72)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.orange.opacity(0.42), lineWidth: 1.5)
                                    )

                                if let raw = placement.logoURL,
                                   let logoURL = URL(string: raw) {
                                    AsyncImage(url: logoURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            sponsorLogoView(image: image, placement: placement)

                                        case .empty:
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .tint(.white)

                                        case .failure:
                                            sponsorFallbackBadge

                                        @unknown default:
                                            sponsorFallbackBadge
                                        }
                                    }
                                } else {
                                    sponsorFallbackBadge
                                }
                            }

                            Text("TAP TO OPEN")
                                .font(DS.Typography.font(7, weight: .black, design: .monospaced, cappedAt: 9))
                                .foregroundColor(.white.opacity(0.58))
                                .tracking(0.9)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .multilineTextAlignment(.center)
                                .frame(width: 76)
                        }
                        .frame(width: 82)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.orange.opacity(0.10),
                                        Color.black.opacity(0.90),
                                        Color.black.opacity(0.98)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .pressScale()
            }
        }
    }

    func adInfoPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Typography.font(7, weight: .black, design: .monospaced, cappedAt: 9))
                .foregroundColor(.white.opacity(0.48))
                .tracking(1.0)

            Text(value)
                .font(DS.Typography.font(10, weight: .black, design: .rounded, cappedAt: 12))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}



// MARK: - Match Actions

private extension GlobalBattleMatchView {

    func lockStagedChoice() {
        guard let uid = myUID else { return }
        guard let staged = stagedChoiceIndex else { return }
        guard !hasLockedAnswer else { return }
        guard !showPresentationOverlay else { return }
        guard !isTieBreakRound else { return }
        
        if hasWinningShot || isPressureMoment || isCriticalAnsweringPhase {
            SpatialAudioManager.shared.play(.dangerPulse)
            HapticManager.instance.impact(.medium)
        }
        SpatialAudioManager.shared.play(.lockIn)

        session.submitAnswerIfPossible(
            currentUID: uid,
            displayName: myDisplayName,
            choiceIndex: staged
        )
    }

    func submitTieBreakChoice(index: Int) {
        guard isTieBreakRound else { return }
        guard let uid = myUID else { return }

        // hard guard against double-tap race
        guard stagedChoiceIndex == nil && !hasLockedAnswer else { return }

        stagedChoiceIndex = index

        guard !hasLockedAnswer else { return }
        guard !showPresentationOverlay else { return }

        SpatialAudioManager.shared.play(.tieBreak)

        session.submitTieBreakTapIfPossible(
            currentUID: uid,
            displayName: myDisplayName,
            choiceIndex: index
        )
    }

    func syncQuestionTimingState() {
        let questionKey = activeQuestionKey.isEmpty ? "nil" : activeQuestionKey
        let phaseKey = "\(currentQuestionNumber)-\(session.roundPhase)-\(questionKey)"

        if session.roundPhase == .waiting {
            if localQuestionKey != phaseKey {
                localQuestionKey = phaseKey
                localQuestionStartAt = nil
                hostAutoRevealQuestion = nil
                hostAutoRevealQuestionKey = ""
                showTieBreakDangerFlash = false
                showPreRevealTension = false
                lastPreRevealTensionKey = ""

                triggerPreRoundPresentationIfNeeded(for: phaseKey)
            }
            return
        }

        if session.roundPhase == .answering {
            if localQuestionKey != phaseKey {
                stagedChoiceIndex = nil
                localQuestionKey = phaseKey
                localQuestionStartAt = now
                hostAutoRevealQuestion = nil
                hostAutoRevealQuestionKey = ""
                showTieBreakDangerFlash = false
                triggerTieBreakDangerIfNeeded()
            }
        }
        else {
            localQuestionKey = phaseKey
            localQuestionStartAt = nil
            hostAutoRevealQuestion = nil
            hostAutoRevealQuestionKey = ""
            showTieBreakDangerFlash = false
        }
    }

    func syncStagedChoice() {
        if hasLockedAnswer {
            stagedChoiceIndex = submittedChoiceIndex
            return
        }

        if session.roundPhase != .answering {
            stagedChoiceIndex = nil
            return
        }

        if let submitted = submittedChoiceIndex {
            stagedChoiceIndex = submitted
            return
        }

        if stagedChoiceIndex != nil, activeQuestionKey.isEmpty {
            stagedChoiceIndex = nil
        }
    }

    func triggerPreRoundPresentationIfNeeded(for phaseKey: String) {
        guard presentationQuestionKey != phaseKey else { return }
        guard !showsWinnerSurface else { return }
        guard session.roundPhase == .waiting else { return }

        presentationQuestionKey = phaseKey

        if currentQuestionNumber == 1 {
            runFirstQuestionCountdown()
            return
        }

        if isTieBreakRound {
            runTieBreakAlert()
            return
        }

        if hasWinningShot || isFinalRegulationRound || isPressureMoment {
            runDecisiveMoment()
            return
        }

        if isApproachingPressureMoment {
            runFinalApproachMoment()
            return
        }

        if pacingBreakRound {
            runMomentumBreak()
        }
    }
    func runFirstQuestionCountdown() {
        presentationTask?.cancel()
        presentationMode = .firstQuestionCountdown
        showPresentationOverlay = true
        countdownValue = 2

        presentationTask = Task {
            if Task.isCancelled { return }

            await MainActor.run {
                countdownValue = 2
                HapticManager.instance.impact(.light)
            }

            try? await Task.sleep(nanoseconds: 1_250_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                countdownValue = 1
                HapticManager.instance.impact(.light)
            }

            try? await Task.sleep(nanoseconds: 1_350_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                countdownValue = 0
                SpatialAudioManager.shared.play(.lockIn)
            }

            try? await Task.sleep(nanoseconds: 1_150_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                showPresentationOverlay = false
                presentationMode = .none
                presentationTask = nil
                inputFrozenUntil = Date().addingTimeInterval(0.35)
            }
        }
    }
    
    func applyPressureAudioState(reason: String) {
        let questionKey = activeQuestionKey.isEmpty ? "round-\(currentQuestionNumber)" : activeQuestionKey

        let pressureBucket: String = {
            if isCriticalAnsweringPhase { return "critical" }
            if isLateAnsweringPhase { return "late" }
            if isTieBreakRound { return "tiebreak" }
            if hasWinningShot { return "winning-shot" }
            if isPressureMoment { return "pressure" }
            if isApproachingPressureMoment { return "approach" }
            return "calm"
        }()

        let key = "\(currentQuestionNumber)-\(questionKey)-\(pressureBucket)-\(reason)"
        guard lastPressureAudioKey != key else { return }

        lastPressureAudioKey = key

        switch pressureBucket {
        case "critical":
            SpatialAudioManager.shared.transition(to: .matchPressure)
            SpatialAudioManager.shared.play(.dangerPulse)
            HapticManager.instance.impact(.light)

        case "late", "tiebreak", "winning-shot", "pressure", "approach":
            SpatialAudioManager.shared.transition(to: .matchPressure)

        default:
            SpatialAudioManager.shared.transition(to: .matchCalm)
        }
    }
    
    func runMomentumBreak() {
        presentationTask?.cancel()
        presentationMode = .momentumBreak
        showPresentationOverlay = true
        SpatialAudioManager.shared.transition(to: .matchCalm)
        SpatialAudioManager.shared.play(.lockIn)

        presentationTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            if Task.isCancelled { return }

            await MainActor.run {
                showPresentationOverlay = false
                presentationMode = .none
                presentationTask = nil
            }
        }
    }

    func runTieBreakAlert() {
        presentationTask?.cancel()
        presentationMode = .tieBreakAlert
        showPresentationOverlay = true
        SpatialAudioManager.shared.transition(to: .matchPressure)
        SpatialAudioManager.shared.play(.tieBreak)

        presentationTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            if Task.isCancelled { return }

            await MainActor.run {
                showPresentationOverlay = false
                presentationMode = .none
                presentationTask = nil
            }
        }
    }
    
    func runFinalApproachMoment() {
        presentationTask?.cancel()
        presentationMode = .finalApproach
        showPresentationOverlay = true
        SpatialAudioManager.shared.transition(to: .matchPressure)
        SpatialAudioManager.shared.play(.dangerPulse)

        presentationTask = Task {
            try? await Task.sleep(nanoseconds: 3_650_000_000)

            if Task.isCancelled { return }

            await MainActor.run {
                showPresentationOverlay = false
                presentationMode = .none
                presentationTask = nil
            }
        }
    }
    
    func runDecisiveMoment() {
        presentationTask?.cancel()
        presentationMode = .decisiveMoment
        showPresentationOverlay = true

        SpatialAudioManager.shared.transition(to: .matchPressure)
        SpatialAudioManager.shared.play(.dangerPulse)
        HapticManager.instance.impact(.heavy)

        presentationTask = Task {
            try? await Task.sleep(nanoseconds: 4_350_000_000)

            if Task.isCancelled { return }

            await MainActor.run {
                showPresentationOverlay = false
                presentationMode = .none
                presentationTask = nil
            }
        }
    }

    func hostRevealIfNeeded() {
        guard iAmHost else { return }
        guard session.phase == .live else { return }
        guard session.roundPhase == .answering else { return }
        guard !activeQuestionKey.isEmpty else { return }
        guard !showPresentationOverlay else { return }
        guard !showPreRevealTension else { return }
        guard presentationTask == nil else { return }
        guard let uid = myUID else { return }

        guard localAnsweringElapsed >= minimumHostAutoRevealDelay else { return }
        guard canRevealCurrentQuestion else { return }

        if hostAutoRevealQuestion == currentQuestionNumber,
           hostAutoRevealQuestionKey == activeQuestionKey {
            return
        }

        // 🔥 DECISIVE MOMENT GATE
        let shouldDelayForImpact =
            hasWinningShot ||
            isFinalRegulationRound ||
            isTieBreakRound

        if shouldDelayForImpact && !showPreRevealTension {
            let previousKey = lastPreRevealTensionKey
            triggerPreRevealTensionIfNeeded()

            // 🔒 If tension did NOT trigger, do not stall reveal
            if lastPreRevealTensionKey == previousKey {
                // no-op → allow reveal to proceed immediately
            } else {
                return
            }
        }

        // 🔥 Slight cinematic delay before reveal
        if shouldDelayForImpact {
            let delayedQuestionNumber = currentQuestionNumber
            let delayedQuestionKey = activeQuestionKey

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard isViewActive else { return }
                guard session.phase == .live else { return }
                guard session.roundPhase == .answering else { return }
                guard currentQuestionNumber == delayedQuestionNumber else { return }
                guard activeQuestionKey == delayedQuestionKey else { return }
                guard !showPresentationOverlay else { return }
                guard !showPreRevealTension else { return }

                let accepted = session.revealCurrentRoundIfHost(currentUID: uid)

                if accepted {
                    hostAutoRevealQuestion = delayedQuestionNumber
                    hostAutoRevealQuestionKey = delayedQuestionKey
                }
            }
            return
        }

        let accepted = session.revealCurrentRoundIfHost(currentUID: uid)

        if accepted {
            hostAutoRevealQuestion = currentQuestionNumber
            hostAutoRevealQuestionKey = activeQuestionKey
        }
    }
    
    func loadSponsorPlacementIfNeeded() {
        guard sponsorPlacement == nil else {
            print("🟨 [Sponsor] skipped load, sponsorPlacement already set")
            return
        }

        guard !isLoadingSponsorPlacement else {
            print("🟨 [Sponsor] skipped load, already loading")
            return
        }

        isLoadingSponsorPlacement = true
        print("🟧 [Sponsor] loadSponsorPlacementIfNeeded started")

        Task {
            defer {
                Task { @MainActor in
                    isLoadingSponsorPlacement = false
                }
            }

            do {
                let resolved = try await FirestoreService.shared.fetchActiveGlobalBattleSponsorPlacement()

                await MainActor.run {
                    guard isViewActive else { return }
                    self.sponsorPlacement = resolved
                    print("🟩 [Sponsor] match view resolved sponsorPlacement nil? \(resolved == nil)")
                }
            } catch {
                await MainActor.run {
                    guard isViewActive else { return }
                    self.sponsorPlacement = nil
                    print("🟥 [Sponsor] failed to load sponsor placement: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func triggerTieBreakDangerIfNeeded() {
        
        guard isTieBreakRound else { return }
        guard myMissCount >= 2 else { return }
        guard session.roundPhase == .answering else { return }
        guard !activeQuestionKey.isEmpty else { return }

        let triggerKey = tieBreakDangerKey
        guard lastDangerTriggerKey != triggerKey else { return }

        lastDangerTriggerKey = triggerKey

        SpatialAudioManager.shared.transition(to: .matchPressure)
        SpatialAudioManager.shared.play(.dangerPulse)
        HapticManager.instance.impact(.heavy)

        showTieBreakDangerFlash = true

        Task {
            try? await Task.sleep(nanoseconds: 1_050_000_000)

            await MainActor.run {
                if self.lastDangerTriggerKey == triggerKey {
                    self.showTieBreakDangerFlash = false
                }
            }
        }
    }
    
    func triggerPreRevealTensionIfNeeded() {
        guard !showPreRevealTension else { return }
        guard session.roundPhase == .answering else { return }
        guard !activeQuestionKey.isEmpty else { return }

        // 🔥 Prevent early/weak triggers — allow tension to build first
        guard localAnsweringElapsed >= 2.2 else { return }

        // 🔥 Only real pressure scenarios
        guard hasWinningShot || isPressureMoment || isTieBreakRound else { return }

        // 🔥 Allow either full lock OR critical time window
        let everyoneAnswered = session.submittedAnswerCount() >= max(1, session.playerCount)
        let criticalTime = secondsRemaining <= 3
        guard everyoneAnswered || criticalTime else { return }

        let triggerKey = "\(currentQuestionNumber)-\(activeQuestionKey)-preReveal"
        guard lastPreRevealTensionKey != triggerKey else { return }

        lastPreRevealTensionKey = triggerKey

        SpatialAudioManager.shared.transition(to: .matchPressure)
        SpatialAudioManager.shared.play(.dangerPulse)
        HapticManager.instance.impact(.medium)

        withAnimation(.easeInOut(duration: 0.22)) {
            showPreRevealTension = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_350_000_000)

            await MainActor.run {
                if self.lastPreRevealTensionKey == triggerKey {
                    self.showPreRevealTension = false
                }
            }
        }
    }
    
    func playPressureTransitionOnce(reason: String) {
        let key = "\(currentQuestionNumber)-\(activeQuestionKey)-\(reason)"
        guard lastPressureAudioKey != key else { return }

        lastPressureAudioKey = key
        SpatialAudioManager.shared.transition(to: .matchPressure)
    }

    func playCriticalPressureCueOnce() {
        let key = "\(currentQuestionNumber)-\(activeQuestionKey)-critical"
        guard lastCriticalAudioKey != key else { return }

        lastCriticalAudioKey = key
        SpatialAudioManager.shared.transition(to: .matchPressure)
        SpatialAudioManager.shared.play(.dangerPulse)
    }
    
    func openSponsorLink() {
        guard
            let raw = sponsorPlacement?.destinationURL,
            let url = URL(string: raw)
        else { return }

        sponsorURL = url
        showSponsorSafari = true
    }

    func handleSessionPhaseChange(_ newPhase: GlobalBattleSession.Phase) {
        switch newPhase {
        case .live:
            SpatialAudioManager.shared.transition(to: .matchCalm)

        case .finished:
            SpatialAudioManager.shared.transition(to: .reveal)
            startFinishExperienceIfNeeded()

        default:
            SpatialAudioManager.shared.transition(to: .lobby)
            experienceTask?.cancel()
            experienceTask = nil
            experiencePhase = .live
            stagedFinishOutcome = .none
        }
    }

    func startFinishExperienceIfNeeded() {
        guard experiencePhase == .live else { return }
        guard !showVictoryCinematic else { return }
        guard !didLaunchVictoryCinematic else { return }

        didLaunchVictoryCinematic = true

        presentationTask?.cancel()
        presentationTask = nil
        showPresentationOverlay = false
        presentationMode = .none
        showTieBreakDangerFlash = false
        showPreRevealTension = false

        experienceTask?.cancel()

        experienceTask = Task {
            var resolved = session.finishOutcome != .none
                ? session.finishOutcome
                : resolvedFinishOutcome

            if resolved == .none {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled { return }

                resolved = session.finishOutcome != .none
                    ? session.finishOutcome
                    : resolvedFinishOutcome
            }

            if Task.isCancelled { return }

            await MainActor.run {
                stagedFinishOutcome = resolved
                finishFlightProgress = 0
                finishHeroScale = 1
                finishHeroGlow = 0.22
                showFinishCrownBurst = false
                experiencePhase = .finalQuestionHold
                SpatialAudioManager.shared.transition(to: .reveal)
                HapticManager.instance.impact(.medium)
            }

            try? await Task.sleep(nanoseconds: 850_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                experiencePhase = .decisionPause
                SpatialAudioManager.shared.play(.lockIn)
                HapticManager.instance.impact(.heavy)
            }

            try? await Task.sleep(nanoseconds: 950_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                experiencePhase = .victorFlight
                SpatialAudioManager.shared.playWarpTrigger()
                finishHeroScale = 0.88
                finishHeroGlow = 0.48
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.82)) {
                    finishFlightProgress = 1
                    finishHeroScale = 1.12
                    finishHeroGlow = 0.68
                }
            }

            try? await Task.sleep(nanoseconds: 720_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                showFinishCrownBurst = true
                SpatialAudioManager.shared.transition(
                    to: heroShowsNoWinnerState ? .defeat : .victory
                )
                HapticManager.instance.impact(.heavy)
            }

            try? await Task.sleep(nanoseconds: 360_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                experiencePhase = .live
                experienceTask = nil
                showVictoryCinematic = true
            }
        }
    }
}

// MARK: - Safari Sheet

private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
