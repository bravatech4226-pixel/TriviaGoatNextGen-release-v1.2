//

//  GlobalBattleLobbyView.swift

//  TriviaGoatNextGen

//

//  PURPOSE:

//  Real Global Battle lobby screen

//  - live roster

//  - host controls

//  - join code visible

//  - routes cleanly into live match

//  - stabilized against current GlobalBattleSession

//  - polished: correct start gating, stronger hierarchy,

//    cleaner bottom command dock, better roster balance

//  - share-ready: lobby code + app download link

//  - localization-ready across en / es / fr

//

import SwiftUI

import FirebaseAuth

import UIKit

struct GlobalBattleLobbyView: View {

    @EnvironmentObject private var app: AppState

    @ObservedObject var session: GlobalBattleSession

    @State private var pulseTick: Bool = false

    @State private var isLeavingLobby: Bool = false

    @State private var showShareSheet: Bool = false

    @State private var didCopyCode: Bool = false

    @State private var showLeaveLobbyAlert: Bool = false

    @State private var didRouteToLiveMatch: Bool = false


    private let appDownloadURL: String? = nil

    private var currentUID: String? {

        app.user?.uid ?? Auth.auth().currentUser?.uid

    }

    private var isHost: Bool {

        session.isHost(currentUID: currentUID)

    }

    private var minimumPlayersToStart: Int {

        session.minimumPlayersToStart

    }

    private var canStart: Bool {

        isHost &&

        !session.isBusy &&

        session.canStartMatch &&

        session.playerCount >= minimumPlayersToStart

    }

    private var rosterCountText: String {

        "\(session.playerCount)/\(session.maxPlayers)"

    }

    private var cleanedLobbyCode: String {

        session.lobbyCode.trimmingCharacters(in: .whitespacesAndNewlines)

    }

    private var canShareLobby: Bool {

        !cleanedLobbyCode.isEmpty

    }

    private var shareMessage: String {

        let code = cleanedLobbyCode.isEmpty ? "------" : cleanedLobbyCode

        if let appDownloadURL,

           !appDownloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

            return "global.lobby.share.full".localized(code, code, appDownloadURL)

        }

        return "global.lobby.share.code_only".localized(code, code)

    }

    var body: some View {

        GeometryReader { geo in

            let safeTop = geo.safeAreaInsets.top

            let topPadding = max(0, safeTop - 22)

            ZStack {

                SpaceBackground()

                LinearGradient(

                    colors: [

                        Color.white.opacity(0.02),

                        Color.clear,

                        Color.orange.opacity(0.03)

                    ],

                    startPoint: .topLeading,

                    endPoint: .bottomTrailing

                )

                .ignoresSafeArea()

                .allowsHitTesting(false)

                VStack(spacing: 10) {

                    topBar

                    codeCard

                    lobbyStateCard

                    rosterCard

                    controlsCard

                    Spacer(minLength: 0)

                }

                .padding(.horizontal, 16)

                .padding(.top, topPadding)

                .padding(.bottom, 10)

            }

        }

        .navigationBarHidden(true)

        .safeAreaInset(edge: .bottom, spacing: 0) {

            bottomDock

                .padding(.horizontal, 16)

                .padding(.top, 8)

                .padding(.bottom, 10)

                .background(

                    Rectangle()

                        .fill(Color.black.opacity(0.94))

                        .ignoresSafeArea()

                )

        }

        .sheet(isPresented: $showShareSheet) {

            ActivityViewController(activityItems: [shareMessage])

        }

        .alert("global.lobby.leave.title".localized, isPresented: $showLeaveLobbyAlert) {

            Button("global.lobby.leave.stay".localized, role: .cancel) { }

            Button("global.lobby.leave.confirm".localized, role: .destructive) {

                guard !isLeavingLobby else { return }

                isLeavingLobby = true

                let uid = currentUID

                session.leaveLobby(currentUID: uid)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {

                    app.exitGlobalBattleToHQ()

                }

            }

        } message: {

            Text("global.lobby.leave.body".localized)

        }

        .onAppear {

            guard app.canAccessGlobalBattle else {
                isLeavingLobby = true
                session.leaveLobby(currentUID: currentUID)
                app.setRoute(.proPaywall)
                return
            }

            isLeavingLobby = false

            didRouteToLiveMatch = false

            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {

                pulseTick.toggle()

            }

        }

        .onReceive(session.$phase) { phase in

            guard !isLeavingLobby else { return }

            guard !didRouteToLiveMatch else { return }

            if phase == .live {

                didRouteToLiveMatch = true

                app.enterGlobalBattleMatch()

            }

        }

    }

}

// MARK: - Share Sheet Helper

struct ActivityViewController: UIViewControllerRepresentable {

    let activityItems: [Any]

    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {

        UIActivityViewController(

            activityItems: activityItems,

            applicationActivities: applicationActivities

        )

    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

}

// MARK: - Layout

private extension GlobalBattleLobbyView {

    var topBar: some View {

        HStack(spacing: 12) {

            Button {

                guard !isLeavingLobby else { return }

                HapticManager.instance.impact(.light)

                showLeaveLobbyAlert = true

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

            .disabled(isLeavingLobby)

            VStack(alignment: .leading, spacing: 3) {

                Text("global.lobby.title".localized)

                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))

                    .foregroundColor(.orange.opacity(0.96))

                    .tracking(1.6)

                Text(isHost ? "global.lobby.host_command".localized : "global.lobby.host_standing_by".localized)

                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 12))

                    .foregroundColor(.white.opacity(0.40))

                    .tracking(1.1)

            }

            Spacer()

            Button {

                guard canShareLobby else { return }

                HapticManager.instance.impact(.light)

                showShareSheet = true

            } label: {

                HStack(spacing: 8) {

                    Image(systemName: "square.and.arrow.up")

                        .font(.system(size: 12, weight: .black))

                    Text("common.share".localized)

                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))

                        .tracking(1.0)

                }

                .foregroundColor(.white.opacity(0.90))

                .padding(.horizontal, 12)

                .frame(height: 36)

                .background(Capsule().fill(Color.white.opacity(0.06)))

                .overlay(

                    Capsule()

                        .stroke(Color.white.opacity(0.10), lineWidth: 1)

                )

            }

            .buttonStyle(.plain)

            .pressScale()

            .disabled(!canShareLobby)

            .opacity(canShareLobby ? 1.0 : 0.45)

        }

    }

    var codeCard: some View {

        VStack(alignment: .leading, spacing: 8) {

            HStack(alignment: .firstTextBaseline) {

                Text("global.lobby.code".localized)

                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))

                    .foregroundColor(.orange.opacity(0.90))

                    .tracking(1.2)

                Spacer()

                HStack(spacing: 10) {

                    Button {

                        guard canShareLobby else { return }

                        UIPasteboard.general.string = cleanedLobbyCode

                        HapticManager.instance.impact(.light)

                        withAnimation(.easeInOut(duration: 0.18)) {

                            didCopyCode = true

                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {

                            withAnimation(.easeInOut(duration: 0.18)) {

                                didCopyCode = false

                            }

                        }

                    } label: {

                        Text(didCopyCode ? "common.copied".localized : "common.copy".localized)

                            .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))

                            .foregroundColor(.white.opacity(0.72))

                            .tracking(1.0)

                    }

                    .buttonStyle(.plain)

                    .disabled(!canShareLobby)

                    Button {

                        guard canShareLobby else { return }

                        HapticManager.instance.impact(.light)

                        showShareSheet = true

                    } label: {

                        Text("common.share".localized)

                            .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))

                            .foregroundColor(.white.opacity(0.72))

                            .tracking(1.0)

                    }

                    .buttonStyle(.plain)

                    .disabled(!canShareLobby)

                }

                .opacity(canShareLobby ? 1 : 0)

            }

            Text(cleanedLobbyCode.isEmpty ? "------" : cleanedLobbyCode)

                .font(DS.Typography.font(28, weight: .black, design: .monospaced, cappedAt: 34))

                .foregroundColor(.white.opacity(0.98))

                .tracking(3)

            Text("global.lobby.code_help".localized)

                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))

                .foregroundColor(.white.opacity(0.60))

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

    }

    var lobbyStateCard: some View {

        HStack(spacing: 10) {

            lobbyPill(title: "global.lobby.players".localized, value: "\(session.playerCount)")

            lobbyPill(title: "global.lobby.max".localized, value: "\(session.maxPlayers)")

            lobbyPill(title: "global.lobby.status".localized, value: lobbyStatusText)

        }

    }

    func lobbyPill(title: String, value: String) -> some View {

        VStack(spacing: 4) {

            Text(title)

                .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))

                .foregroundColor(.white.opacity(0.45))

                .tracking(1.0)

            Text(value)

                .font(DS.Typography.font(13, weight: .black, design: .rounded, cappedAt: 16))

                .foregroundColor(.white.opacity(0.94))

                .lineLimit(1)

                .minimumScaleFactor(0.75)

        }

        .frame(maxWidth: .infinity)

        .padding(.vertical, 10)

        .background(

            RoundedRectangle(cornerRadius: 14, style: .continuous)

                .fill(Color.white.opacity(0.06))

        )

        .overlay(

            RoundedRectangle(cornerRadius: 14, style: .continuous)

                .stroke(Color.white.opacity(0.10), lineWidth: 1)

        )

    }

    var rosterCard: some View {

        VStack(alignment: .leading, spacing: 10) {

            HStack {

                Text("global.lobby.live_roster".localized)

                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))

                    .foregroundColor(.white.opacity(0.50))

                    .tracking(1.1)

                Spacer()

                Text(rosterCountText)

                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))

                    .foregroundColor(.white.opacity(0.40))

                    .tracking(1.0)

            }

            if session.participants.isEmpty {

                Text("global.lobby.no_pilots".localized)

                    .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))

                    .foregroundColor(.white.opacity(0.58))

                    .frame(maxWidth: .infinity, alignment: .leading)

                    .padding(.horizontal, 12)

                    .padding(.vertical, 14)

                    .background(

                        RoundedRectangle(cornerRadius: 14, style: .continuous)

                            .fill(Color.white.opacity(0.05))

                    )

                    .overlay(

                        RoundedRectangle(cornerRadius: 14, style: .continuous)

                            .stroke(Color.white.opacity(0.08), lineWidth: 1)

                    )

            } else {

                ScrollView(showsIndicators: false) {

                    VStack(spacing: 8) {

                        ForEach(session.participants, id: \.uid) { player in

                            rosterRow(player)

                        }

                    }

                    .padding(.vertical, 1)

                }

                .frame(maxHeight: 228)

            }

        }

        .tacticalPanel()

    }

    func rosterRow(_ player: GlobalBattleParticipant) -> some View {

        let isMe = player.uid == currentUID

        return HStack(spacing: 10) {

            Circle()

                .fill(player.isHost ? Color.orange.opacity(0.92) : Color.white.opacity(0.26))

                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {

                HStack(spacing: 8) {

                    Text(player.displayName.uppercased())

                        .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))

                        .foregroundColor(.white.opacity(0.92))

                        .lineLimit(1)

                        .minimumScaleFactor(0.80)

                    if isMe {

                        Text("common.you".localized)

                            .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))

                            .foregroundColor(.black)

                            .padding(.horizontal, 6)

                            .padding(.vertical, 3)

                            .background(Capsule().fill(Color.white.opacity(0.92)))

                    }

                }

                Text(player.isHost ? "global.lobby.host".localized : "global.lobby.pilot".localized)

                    .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))

                    .foregroundColor(player.isHost ? .orange.opacity(0.86) : .white.opacity(0.42))

                    .tracking(0.8)

            }

            Spacer()

            Text("\(player.score) \("global.lobby.points".localized)")

                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))

                .foregroundColor(.white.opacity(0.62))

                .tracking(0.8)

        }

        .padding(.horizontal, 12)

        .frame(height: 48)

        .background(

            RoundedRectangle(cornerRadius: 14, style: .continuous)

                .fill(Color.white.opacity(0.05))

        )

        .overlay(

            RoundedRectangle(cornerRadius: 14, style: .continuous)

                .stroke(Color.white.opacity(0.08), lineWidth: 1)

        )

    }

    var controlsCard: some View {

        VStack(spacing: 10) {

            if isHost {

                Button {

                    HapticManager.instance.impact(.light)

                    guard let uid = currentUID else { return }

                    session.startMatchIfHost(currentUID: uid)

                } label: {

                    Text(session.isBusy ? "global.lobby.launching".localized : "global.lobby.start_match".localized)

                        .font(DS.Typography.font(15, weight: .black, design: .rounded, cappedAt: 19))

                        .frame(maxWidth: .infinity)

                        .frame(height: 52)

                }

                .buttonStyle(ChunkyButtonStyle(color: .orange))

                .pressScale()

                .disabled(!canStart)

                .opacity(canStart ? 1.0 : 0.70)

                if !canStart {

                    Text("global.lobby.need_players".localized(minimumPlayersToStart))

                        .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 13))

                        .foregroundColor(.white.opacity(0.54))

                        .multilineTextAlignment(.center)

                }

            } else {

                VStack(spacing: 6) {

                    Text("global.lobby.host_will_launch".localized)

                        .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))

                        .foregroundColor(.orange.opacity(0.86))

                        .tracking(1.0)

                    Text("global.lobby.wait_for_host_body".localized)

                        .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))

                        .foregroundColor(.white.opacity(0.62))

                        .multilineTextAlignment(.center)

                        .padding(.horizontal, 6)

                }

            }

            if !session.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                Text(session.statusMessage)

                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 13))

                    .foregroundColor(.orange.opacity(0.86))

                    .multilineTextAlignment(.center)

            }

        }

        .tacticalPanel()

    }

    var bottomDock: some View {

        HStack(spacing: 12) {

            VStack(alignment: .leading, spacing: 4) {

                Text("global.lobby.command_status".localized)

                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))

                    .foregroundColor(.white.opacity(0.46))

                    .tracking(1.0)

                Text(bottomHeadline)

                    .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))

                    .foregroundColor(.white.opacity(0.94))

                    .lineLimit(1)

                    .minimumScaleFactor(0.80)

            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {

                Text("global.lobby.roster".localized)

                    .font(DS.Typography.font(8, weight: .black, design: .monospaced, cappedAt: 10))

                    .foregroundColor(.white.opacity(0.40))

                    .tracking(1.0)

                Text(rosterCountText)

                    .font(DS.Typography.font(18, weight: .black, design: .rounded, cappedAt: 22))

                    .foregroundColor(.orange.opacity(0.95))

            }

        }

        .padding(.horizontal, 16)

        .padding(.vertical, 14)

        .background(

            RoundedRectangle(cornerRadius: 20, style: .continuous)

                .fill(Color.black.opacity(0.96))

                .overlay(

                    RoundedRectangle(cornerRadius: 20, style: .continuous)

                        .stroke(Color.orange.opacity(pulseTick ? 0.26 : 0.14), lineWidth: 1.3)

                )

        )

    }

    var bottomHeadline: String {

        if session.isBusy {

            return "global.lobby.syncing_state".localized

        }

        if isHost {

            return canStart

                ? "global.lobby.you_control_launch".localized

                : "global.lobby.waiting_more_pilots".localized

        }

        return "global.lobby.waiting_for_host".localized

    }

    var lobbyStatusText: String {

        switch session.phase {

        case .idle:

            return "global.lobby.phase.idle".localized

        case .creating:

            return "global.lobby.phase.creating".localized

        case .joining:

            return "global.lobby.phase.joining".localized

        case .lobby:

            return "global.lobby.phase.ready".localized

        case .live:

            return "global.lobby.phase.live".localized

        case .finished:

            return "global.lobby.phase.done".localized

        case .failed:

            return "global.lobby.phase.error".localized

        }

    }

}
