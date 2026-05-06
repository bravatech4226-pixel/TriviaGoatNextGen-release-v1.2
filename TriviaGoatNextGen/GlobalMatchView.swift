//
//  GlobalMatchView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-03-15.
//
//  PURPOSE:
//  Global Battle landing + create/join entry
//  - compile-safe with current AppState
//  - wired to GlobalBattleSession
//  - safe-area correct
//  - real lobby handoff
//  - admin-access aware gating
//  - debug instrumentation for create/join path
//  - stabilized route / lobby handoff behavior
//  - avoids publishing changes during view updates
//  - hardened against existing session reuse
//  - improved join field readability
//  - localization-ready across en / es / fr
//

import SwiftUI
import FirebaseAuth
import Combine

struct GlobalMatchView: View {
    @EnvironmentObject private var app: AppState

    @State private var joinCodeText: String = ""
    @State private var hazeDrift: Bool = false
    @State private var pulseTick: Bool = false
    @State private var showLobby: Bool = false
    @State private var isRoutingAway: Bool = false
    @State private var phaseCancellable: AnyCancellable? = nil

    private var session: GlobalBattleSession? {
        app.globalBattleSession
    }

    private var sessionIsBusy: Bool {
        session?.isBusy ?? false
    }

    private var canUseGlobalBattleControls: Bool {
        app.canAccessGlobalBattle
    }

    private func debugTapCheckpoint(label: String) {
        #if DEBUG
        print(
            """
            🛰️ [GlobalBattle] \(label)
               route: \(String(describing: app.route))
               canUseGlobalBattleControls: \(canUseGlobalBattleControls)
               app.isGlobalBattleEnabled: \(app.isGlobalBattleEnabled)
               app.user.uid: \(app.user?.uid ?? "nil")
               session exists: \(app.globalBattleSession != nil)
               sessionIsBusy: \(app.globalBattleSession?.isBusy ?? false)
               session phase: \(String(describing: app.globalBattleSession?.phase))
               session status: \(app.globalBattleSession?.statusMessage ?? "nil")
               showLobby: \(showLobby)
               isRoutingAway: \(isRoutingAway)
            """
        )
        #endif
    }

    var body: some View {
        Group {
            if showLobby, let session = session {
                GlobalBattleLobbyView(session: session)
                    .environmentObject(app)
            } else {
                landingView
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if app.globalBattleSession == nil {
                _ = app.ensureGlobalBattleSession()
            }

            isRoutingAway = false
            syncSurfaceToSession()

            debugTapCheckpoint(label: "SCREEN APPEAR")

            withAnimation(.easeInOut(duration: 8.5).repeatForever(autoreverses: true)) {
                hazeDrift.toggle()
            }

            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                pulseTick.toggle()
            }
        }
        .onAppear {
            installPhaseObserver()
        }
        .onChange(of: app.globalBattleSession?.localLobbyID) { _, _ in
            guard !isRoutingAway else { return }

            DispatchQueue.main.async {
                guard !isRoutingAway else { return }
                syncSurfaceToSession()
            }
        }
        .onChange(of: app.globalBattleSession?.runtime?.phase) { _, _ in
            guard !isRoutingAway else { return }

            DispatchQueue.main.async {
                guard !isRoutingAway else { return }
                syncSurfaceToSession()
            }
        }
    }

    private func isSessionInLobbyPhase() -> Bool {
        guard let session = app.globalBattleSession else { return false }
        if case .lobby = session.phase { return true }
        return false
    }

    private func isSessionInLivePhase() -> Bool {
        guard let session = app.globalBattleSession else { return false }
        if case .live = session.phase { return true }
        return false
    }

    private func handlePhaseUpdate(_ phase: GlobalBattleSession.Phase) {
        switch phase {
        case .idle:
            showLobby = false

        case .creating, .joining:
            showLobby = false

        case .lobby:
            #if DEBUG
            print("🪩 [GlobalBattle] showing lobby")
            #endif
            showLobby = true

        case .live:
            showLobby = false

            if app.route != .globalBattleMatch {
                isRoutingAway = true
                #if DEBUG
                print("🎯 [GlobalBattle] entering match route")
                #endif
                app.enterGlobalBattleMatch()
            }

        case .finished:
            showLobby = false
            #if DEBUG
            print("🏁 [GlobalBattle] phase finished")
            #endif

        case .failed(let message):
            showLobby = false
            #if DEBUG
            print("❌ [GlobalBattle] phase failed: \(message)")
            #endif
        }
    }

    private func syncSurfaceToSession() {
        if isSessionInLivePhase() {
            showLobby = false

            if app.route != .globalBattleMatch {
                isRoutingAway = true
                app.enterGlobalBattleMatch()
            }
            return
        }

        showLobby = isSessionInLobbyPhase()
    }
}

// MARK: - Landing

private extension GlobalMatchView {

    private func installPhaseObserver() {
        phaseCancellable?.cancel()

        guard let session = app.globalBattleSession else { return }

        phaseCancellable = session.$phase
            .receive(on: RunLoop.main)
            .sink { phase in
                #if DEBUG
                print("📡 [GlobalBattle] phase update: \(phase)")
                #endif

                guard !isRoutingAway else { return }

                DispatchQueue.main.async {
                    guard !isRoutingAway else { return }
                    handlePhaseUpdate(phase)
                }
            }
    }

    var landingView: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let topPadding = max(0, safeTop - 22)

            ZStack {
                SpaceBackground()

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.clear,
                        Color.orange.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                AmbientHaze(drift: hazeDrift)
                    .opacity(0.16)
                    .allowsHitTesting(false)

                VStack(spacing: 8) {
                    topBar

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            launchStatusCard
                            heroCard
                            integrationStateCard
                            currentPlanCard
                            actionPanel
                        }
                        .padding(.top, 0)
                        .padding(.bottom, max(140, geo.safeAreaInsets.bottom + 110))
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .padding(.horizontal, 16)
                .padding(.top, topPadding)
                .padding(.bottom, 6)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomDock
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.62),
                            Color.black.opacity(0.96)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
        }
    }

    var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                HapticManager.instance.impact(.light)
                isRoutingAway = true

                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    app.exitGlobalBattleToHQ()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                    .foregroundColor(.white.opacity(0.90))
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
                Text("global.entry.title".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.orange.opacity(0.96))
                    .tracking(1.8)

                Text("global.entry.subtitle".localized)
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.40))
                    .tracking(1.2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Image(systemName: "globe.americas.fill")
                    .font(DS.Typography.font(12, weight: .black, design: .default, cappedAt: 14))
                    .foregroundColor(.orange.opacity(0.92))

                Text(canUseGlobalBattleControls ? "global.entry.live".localized : "global.entry.offline".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.84))
                    .tracking(1.0)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
    }

    var launchStatusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 42, height: 42)

                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(DS.Typography.font(18, weight: .black, design: .default, cappedAt: 22))
                    .foregroundColor(.orange.opacity(0.95))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("global.entry.launch_control".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.50))
                    .tracking(1.0)

                Text(
                    canUseGlobalBattleControls
                    ? "global.entry.access_enabled".localized
                    : "global.entry.access_disabled".localized
                )
                .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))
                .foregroundColor(.white.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("global.entry.world_stage".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.orange.opacity(0.90))
                    .tracking(1.2)

                Spacer()

                Text("global.entry.live_network".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.44))
                    .tracking(1.0)
            }

            Text("global.entry.hero_body".localized)
                .font(DS.Typography.font(24, weight: .black, design: .rounded, cappedAt: 32))
                .foregroundColor(.white.opacity(0.98))
                .fixedSize(horizontal: false, vertical: true)

            Text("global.entry.hero_warning".localized)
                .font(DS.Typography.font(13, weight: .semibold, design: .rounded, cappedAt: 17))
                .foregroundColor(.orange.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.03),
                            Color.clear,
                            Color.orange.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
    }

    var integrationStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("global.entry.current_state".localized)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.50))
                .tracking(1.2)

            statusRow(
                icon: "checkmark.circle.fill",
                title: "global.entry.state.shell".localized,
                subtitle: "global.entry.ready".localized
            )

            statusRow(
                icon: "checkmark.circle.fill",
                title: "global.entry.state.session".localized,
                subtitle: "global.entry.state.session_ready".localized
            )

            statusRow(
                icon: "checkmark.circle.fill",
                title: "global.entry.state.roster".localized,
                subtitle: "global.entry.state.listener_ready".localized
            )

            statusRow(
                icon: "checkmark.circle.fill",
                title: "global.entry.state.handoff".localized,
                subtitle: "global.entry.state.stabilized".localized
            )

            statusRow(
                icon: canUseGlobalBattleControls ? "checkmark.circle.fill" : "clock.fill",
                title: "global.entry.state.access".localized,
                subtitle: canUseGlobalBattleControls
                    ? "global.entry.state.access_enabled".localized
                    : "global.entry.state.access_disabled".localized
            )
        }
        .tacticalPanel()
    }

    func statusRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 16))
                .foregroundColor(icon.contains("checkmark") ? .green.opacity(0.92) : .orange.opacity(0.88))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typography.font(13, weight: .black, design: .rounded, cappedAt: 17))
                    .foregroundColor(.white.opacity(0.94))

                Text(subtitle.uppercased())
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(.white.opacity(0.48))
                    .tracking(1.0)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    var currentPlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("global.entry.live_flow".localized)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.50))
                .tracking(1.2)

            planChip("1", "global.entry.flow.host_create".localized)
            planChip("2", "global.entry.flow.join_code".localized)
            planChip("3", "global.entry.flow.lock_answer".localized)
            planChip("4", "global.entry.flow.sync_live".localized)
        }
        .tacticalPanel()
    }

    func planChip(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 28, height: 28)

                Text(number)
                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.orange.opacity(0.94))
            }

            Text(text)
                .font(DS.Typography.font(13, weight: .bold, design: .rounded, cappedAt: 17))
                .foregroundColor(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    var actionPanel: some View {
        VStack(spacing: 12) {
            Button {
                HapticManager.instance.impact(.light)
                debugTapCheckpoint(label: "CREATE TAP START")

                guard canUseGlobalBattleControls else {
                    #if DEBUG
                    print("🛑 [GlobalBattle] Create blocked: canUseGlobalBattleControls == false")
                    #endif
                    return
                }

                guard let uid = app.user?.uid,
                      !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    #if DEBUG
                    print("🛑 [GlobalBattle] Create blocked: app.user?.uid is nil/empty")
                    #endif
                    return
                }

                let session = app.globalBattleSession ?? app.ensureGlobalBattleSession()
                let dayKey = DailyMission.snapshot(
                    uid: app.user?.uid,
                    team: app.profile.team
                ).dayKey

                #if DEBUG
                print("✅ [GlobalBattle] Create continuing with session + uid: \(uid)")
                print("🧪 [GlobalBattle] createLobby params")
                print("   displayName: \(app.profile.displayName)")
                print("   topic: General Knowledge")
                print("   dayKey: \(dayKey)")
                print("   maxPlayers: 50")
                print("   questionCount: 10")
                #endif

                isRoutingAway = false
                showLobby = false

                session.createLobby(
                    hostUID: uid,
                    displayName: app.profile.displayName,
                    topic: "General Knowledge",
                    dayKey: dayKey,
                    maxPlayers: 50,
                    questionCount: 10
                )

                #if DEBUG
                print("🚀 [GlobalBattle] createLobby invoked")
                #endif
            } label: {
                Text(sessionIsBusy && isCreatingPhase ? "global.entry.creating".localized : "global.entry.create_lobby".localized)
                    .font(DS.Typography.font(15, weight: .black, design: .rounded, cappedAt: 19))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(ChunkyButtonStyle(color: .orange))
            .pressScale()
            .disabled(!canUseGlobalBattleControls || sessionIsBusy)
            .opacity(canUseGlobalBattleControls ? 1.0 : 0.55)

            VStack(alignment: .leading, spacing: 8) {
                Text("global.entry.join_by_code".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.50))
                    .tracking(1.1)

                TextField(
                    "",
                    text: $joinCodeText,
                    prompt: Text("global.entry.enter_code".localized)
                        .foregroundColor(.white.opacity(0.52))
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .font(DS.Typography.font(16, weight: .black, design: .monospaced, cappedAt: 18))
                .foregroundColor(.white.opacity(0.96))
                .tint(.orange)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
                .onChange(of: joinCodeText) { _, newValue in
                    let filtered = newValue
                        .uppercased()
                        .filter { $0.isLetter || $0.isNumber }
                    joinCodeText = String(filtered.prefix(6))
                }

                Button {
                    HapticManager.instance.impact(.light)
                    debugTapCheckpoint(label: "JOIN TAP START")

                    guard canUseGlobalBattleControls else {
                        #if DEBUG
                        print("🛑 [GlobalBattle] Join blocked: canUseGlobalBattleControls == false")
                        #endif
                        return
                    }

                    guard let uid = app.user?.uid,
                          !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        #if DEBUG
                        print("🛑 [GlobalBattle] Join blocked: app.user?.uid is nil/empty")
                        #endif
                        return
                    }

                    let session = app.globalBattleSession ?? app.ensureGlobalBattleSession()

                    #if DEBUG
                    print("✅ [GlobalBattle] Join continuing with uid: \(uid)")
                    print("🧪 [GlobalBattle] joinLobby code: \(joinCodeText)")
                    #endif

                    isRoutingAway = false
                    showLobby = false

                    session.joinLobby(
                        code: joinCodeText,
                        uid: uid,
                        displayName: app.profile.displayName
                    )

                    #if DEBUG
                    print("🚀 [GlobalBattle] joinLobby invoked")
                    #endif
                } label: {
                    Text(sessionIsBusy && isJoiningPhase ? "global.entry.joining".localized : "global.entry.join_lobby".localized)
                        .font(DS.Typography.font(15, weight: .black, design: .rounded, cappedAt: 19))
                        .foregroundColor(.white.opacity(0.96))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(ChunkyButtonStyle(color: Color.white.opacity(0.28)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .pressScale()
                .disabled(!canUseGlobalBattleControls || sessionIsBusy || joinCodeText.count < 6)

                if let statusMessage = session?.statusMessage,
                   !statusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(statusMessage)
                        .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.orange.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }

                if let lobbyCode = session?.lobbyCode,
                   !lobbyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("global.entry.active_code".localized(lobbyCode))
                        .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                        .foregroundColor(.white.opacity(0.80))
                        .tracking(1.0)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }

            Text("global.entry.action_help".localized)
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.56))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .tacticalPanel()
    }

    var bottomDock: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("global.entry.status".localized)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .foregroundColor(.white.opacity(0.48))
                    .tracking(1.0)

                Text(bottomStatusText)
                    .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))
                    .foregroundColor(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.orange.opacity(pulseTick ? 0.95 : 0.45))
                    .frame(width: 10, height: 10)

                Text(canUseGlobalBattleControls ? "global.entry.live".localized : "global.entry.off".localized)
                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.84))
                    .tracking(1.0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.orange.opacity(pulseTick ? 0.28 : 0.14), lineWidth: 1.4)
                )
                .shadow(color: .black.opacity(0.60), radius: 22, x: 0, y: 14)
                .shadow(color: .orange.opacity(0.10), radius: 20, x: 0, y: 12)
        )
    }

    var isCreatingPhase: Bool {
        guard let session = session else { return false }
        if case .creating = session.phase { return true }
        return false
    }

    var isJoiningPhase: Bool {
        guard let session = session else { return false }
        if case .joining = session.phase { return true }
        return false
    }

    var bottomStatusText: String {
        guard let session = session else { return "global.entry.phase.standby".localized }

        switch session.phase {
        case .idle:
            return "global.entry.phase.standby".localized
        case .creating:
            return "global.entry.phase.creating_lobby".localized
        case .joining:
            return "global.entry.phase.joining_lobby".localized
        case .lobby:
            return "global.entry.phase.lobby_ready".localized
        case .live:
            return "global.entry.phase.match_live".localized
        case .finished:
            return "global.entry.phase.match_finished".localized
        case .failed:
            return "global.entry.phase.action_failed".localized
        }
    }
}

// MARK: - Support

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
