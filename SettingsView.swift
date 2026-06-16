//
//  SettingsView.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-03-04.
//

import SwiftUI
import StoreKit
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    @AppStorage("audioEnabled") private var audioEnabled: Bool = true
    @StateObject private var readability = ReadabilityManager.shared

    @State private var selectedAvatarStyle: String = ""
    @State private var selectedAvatarSeed: String = ""

    private let shareText = "TriviaGOAT — fast, brutal trivia battles. 🐐⚡️"
    private let shareURL = URL(string: "https://triviagoat.ca")!

    private let supportURL = URL(string: "https://triviagoat.ca/support")!
    private let privacyURL = URL(string: "https://triviagoat.ca/privacy")!
    private let termsURL = URL(string: "https://triviagoat.ca/terms")!

    private let avatarChoices: [AvatarChoice] = AvatarChoice.curated

    var body: some View {
        let appRef = app

        ZStack {
            SpaceBackground()

            VStack(spacing: 16) {
                header(appRef: appRef)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        profilePanel(appRef: appRef)
                        eventOpsPanel(appRef: appRef)
                        readabilityPanel()
                        audioPanel()
                        sharePanel()
                        legalSupportPanel()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }

                footer(appRef: appRef)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
            .padding(.top, 14)
        }
        .navigationBarHidden(true)
        .onAppear {
            selectedAvatarStyle = app.profile.avatarStyle.isEmpty
                ? AvatarChoice.defaultChoice.style
                : app.profile.avatarStyle

            selectedAvatarSeed = app.profile.avatarSeed.isEmpty
                ? AvatarChoice.defaultChoice.seed
                : app.profile.avatarSeed

            if audioEnabled {
                SpatialAudioManager.shared.refreshAudioState()
            } else {
                SpatialAudioManager.shared.stopAll()
                SpatialAudioManager.shared.stopBGM()
            }
        }
        .onChange(of: audioEnabled) { _, newValue in
            HapticManager.instance.impact(.light)

            if newValue {
                SpatialAudioManager.shared.refreshAudioState()
                SpatialAudioManager.shared.play(.uiTap)
            } else {
                SpatialAudioManager.shared.stopAll()
                SpatialAudioManager.shared.stopBGM()
            }
        }
    }
}

// MARK: - Review Prompt

private enum ReviewPrompter {
    static func requestReview() {
        if #available(iOS 18.0, *) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            else { return }

            Task { @MainActor in
                AppStore.requestReview(in: scene)
            }
        } else {
            SKStoreReviewController.requestReview()
        }
    }
}

// MARK: - Avatar Choice

private struct AvatarChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let style: String
    let seed: String
    let symbol: String

    static let defaultChoice = AvatarChoice(
        id: "adventurer-goat-alpha",
        title: "GOAT ALPHA",
        style: "adventurer",
        seed: "TriviaGoatAlpha",
        symbol: "bolt.shield.fill"
    )

    static let curated: [AvatarChoice] = [
        .init(id: "adventurer-goat-alpha", title: "GOAT ALPHA", style: "adventurer", seed: "TriviaGoatAlpha", symbol: "bolt.shield.fill"),
        .init(id: "adventurer-titan", title: "TITAN", style: "adventurer", seed: "TitanPilot", symbol: "shield.lefthalf.filled"),
        .init(id: "adventurer-orbit", title: "ORBIT", style: "adventurer", seed: "OrbitAce", symbol: "scope"),
        .init(id: "adventurer-rogue", title: "ROGUE", style: "adventurer", seed: "RogueMind", symbol: "flame.fill"),
        .init(id: "avataaars-pilot-ace", title: "PILOT ACE", style: "avataaars", seed: "PilotAce", symbol: "airplane"),
        .init(id: "avataaars-striker", title: "STRIKER", style: "avataaars", seed: "StrikerPrime", symbol: "bolt.fill"),
        .init(id: "avataaars-captain", title: "CAPTAIN", style: "avataaars", seed: "CaptainNova", symbol: "star.fill"),
        .init(id: "avataaars-maverick", title: "MAVERICK", style: "avataaars", seed: "MaverickGoat", symbol: "paperplane.fill"),
        .init(id: "bottts-core", title: "BOT CORE", style: "bottts", seed: "BotCore77", symbol: "cpu.fill"),
        .init(id: "bottts-byte", title: "BYTE", style: "bottts", seed: "BytePilot", symbol: "memorychip.fill"),
        .init(id: "bottts-neural", title: "NEURAL", style: "bottts", seed: "NeuralGoat", symbol: "brain.head.profile"),
        .init(id: "bottts-sentinel", title: "SENTINEL", style: "bottts", seed: "Sentinel99", symbol: "antenna.radiowaves.left.and.right"),
        .init(id: "notionists-luxe", title: "LUXE MIND", style: "notionists", seed: "LuxeMind", symbol: "sparkles"),
        .init(id: "notionists-oracle", title: "ORACLE", style: "notionists", seed: "OracleRun", symbol: "eye.fill"),
        .init(id: "notionists-zenith", title: "ZENITH", style: "notionists", seed: "ZenithIQ", symbol: "mountain.2.fill"),
        .init(id: "icons-neon", title: "NEON ICON", style: "icons", seed: "NeonIcon", symbol: "hexagon.fill"),
        .init(id: "icons-vault", title: "VAULT", style: "icons", seed: "VaultPilot", symbol: "lock.shield.fill"),
        .init(id: "icons-crown", title: "CROWN", style: "icons", seed: "CrownMode", symbol: "crown.fill"),
        .init(id: "initials-tg", title: "TG MONO", style: "initials", seed: "TriviaGoat", symbol: "textformat"),
        .init(id: "initials-ace", title: "ACE", style: "initials", seed: "ACE", symbol: "a.square.fill")
    ]
}

// MARK: - App Version Helper

private func appVersionString() -> String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    return "TriviaGOAT v\(version) (\(build))"
}

// MARK: - Sections

private extension SettingsView {

    var activeAvatarChoice: AvatarChoice {
        avatarChoices.first {
            $0.style == selectedAvatarStyle && $0.seed == selectedAvatarSeed
        } ?? AvatarChoice.defaultChoice
        
    }

    func avatarURL(for choice: AvatarChoice) -> URL? {
        let style = choice.style.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? choice.style
        let seed = choice.seed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? choice.seed
        return URL(string: "https://api.dicebear.com/9.x/\(style)/png?seed=\(seed)&size=128")
    }

    func playSettingsTap() {
        guard audioEnabled else { return }
        SpatialAudioManager.shared.play(.uiTap)
    }

    func selectAvatar(_ choice: AvatarChoice) {
        HapticManager.instance.impact(.light)
        playSettingsTap()

        selectedAvatarStyle = choice.style
        selectedAvatarSeed = choice.seed
    }

    func header(appRef: AppState) -> some View {
        HStack {
            Button {
                HapticManager.instance.impact(.light)
                playSettingsTap()

                withAnimation(.spring()) {
                    appRef.setRoute(.hq)
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
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Text("settings.title".localized)
                .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 18)
    }

    func profilePanel(appRef: AppState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionEyebrow("settings.profile".localized)

            HStack(alignment: .center, spacing: 12) {
                AvatarBadgeView(
                    url: avatarURL(for: activeAvatarChoice),
                    fallbackSymbol: activeAvatarChoice.symbol,
                    size: 58
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(resolvedCodename(appRef.profile.displayName))
                        .font(DS.Typography.font(18, weight: .black, design: .rounded, cappedAt: 22))
                        .foregroundColor(.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text("IDENTITY LOCKED")
                        .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 14))
                        .foregroundColor(.orange.opacity(0.88))
                        .tracking(1.2)

                    Text("AVATAR READY")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.white.opacity(0.52))
                        .tracking(1.0)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(DS.Typography.font(10, weight: .black, design: .default, cappedAt: 12))

                    Text("AVATAR")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .tracking(0.8)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color.white))
            }

            VStack(alignment: .leading, spacing: 10) {
                profileInfoRow(label: "TEAM", value: String(describing: appRef.profile.team).uppercased())
                profileInfoRow(label: "XP", value: "\(appRef.profile.xp)")
                profileInfoRow(label: "LEVEL", value: "\(appRef.currentLevel)")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("AVATAR SELECT")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.white.opacity(0.46))
                        .tracking(1.0)

                    Spacer()

                    Text("AVATAR READY")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.white.opacity(0.52))
                        .tracking(1.0)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(avatarChoices) { choice in
                            avatarChoiceCard(choice)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Text("Your codename stays locked here. Choose a pilot avatar freely without changing identity, moderation, or competitive integrity.")
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    rowInfoChip(title: "CODENAME LOCKED", systemImage: "lock.fill")
                    rowInfoChip(title: "AVATAR FLEX", systemImage: "sparkles")
                }

                VStack(alignment: .leading, spacing: 10) {
                    rowInfoChip(title: "CODENAME LOCKED", systemImage: "lock.fill")
                    rowInfoChip(title: "AVATAR FLEX", systemImage: "sparkles")
                }
            }
        }
        .tacticalPanel()
    }
    
    func eventOpsPanel(appRef: AppState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("EVENT OPS")

            Button {
                HapticManager.instance.impact(.light)
                playSettingsTap()

                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    appRef.setRoute(.creatorConsole)
                }
            } label: {
                rowButton(
                    title: "CREATOR CONSOLE",
                    systemImage: "calendar.badge.plus"
                )
            }
            .buttonStyle(.plain)

            Text("Create drafts, manage approved events, and prepare attendee operations.")
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .tacticalPanel()
    }

    func avatarChoiceCard(_ choice: AvatarChoice) -> some View {
        let isSelected = selectedAvatarStyle == choice.style &&
            selectedAvatarSeed == choice.seed

        return Button {
            selectAvatar(choice)
        } label: {
            VStack(spacing: 8) {
                AvatarBadgeView(
                    url: avatarURL(for: choice),
                    fallbackSymbol: choice.symbol,
                    size: 54
                )

                Text(choice.title)
                    .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.90))
                    .tracking(0.8)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 82)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(width: 102, height: 118)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.96) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.0 : 0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func profileInfoRow(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.46))
                .tracking(1.0)
                .frame(width: 58, alignment: .leading)

            Text(value)
                .font(DS.Typography.font(12, weight: .black, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.90))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    func readabilityPanel() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("settings.readability".localized)

            Text("Adjust text size globally for cleaner reading across the app.")
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                readabilityScaleButton(.standard)
                readabilityScaleButton(.large)
                readabilityScaleButton(.extraLarge)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CURRENT")
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.white.opacity(0.46))
                        .tracking(1.0)

                    Spacer()

                    Text(readability.textScale.title.uppercased())
                        .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                        .foregroundColor(.orange.opacity(0.92))
                        .tracking(1.0)
                }

                readabilityPreviewCard
            }
        }
        .tacticalPanel()
    }

    func readabilityScaleButton(_ scale: DS.TextScale) -> some View {
        let isSelected = readability.textScale == scale

        return Button {
            HapticManager.instance.impact(.light)
            readability.setScale(scale)
        } label: {
            VStack(spacing: 6) {
                Text(scale.title.uppercased())
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                    .tracking(0.9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("Aa")
                    .font(
                        DS.Typography.font(
                            sampleFontSize(for: scale),
                            weight: .black,
                            design: .rounded,
                            cappedAt: 18
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 66)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.96) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.0 : 0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var readabilityPreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.44))
                .tracking(1.0)

            Text("Fast, clean, easy-to-read battle text.")
                .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 22))
                .foregroundColor(.white.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)

            Text("This setting helps improve readability across headers, panels, and action labels.")
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                .foregroundColor(.white.opacity(0.60))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    func sampleFontSize(for scale: DS.TextScale) -> CGFloat {
        switch scale {
        case .standard: return 14
        case .large: return 16
        case .extraLarge: return 18
        }
    }

    func audioPanel() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("settings.audio".localized)

            HStack(spacing: 12) {
                Image(systemName: audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(DS.Typography.font(16, weight: .black, design: .default, cappedAt: 20))
                    .foregroundColor(audioEnabled ? .orange.opacity(0.95) : .white.opacity(0.55))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sound Effects + Music")
                        .font(DS.Typography.font(14, weight: .bold, design: .rounded, cappedAt: 18))
                        .foregroundColor(.white.opacity(0.92))

                    Text(audioEnabled ? "Audio is ON." : "Audio is OFF.")
                        .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 15))
                        .foregroundColor(.white.opacity(0.55))
                }

                Spacer()

                Toggle("", isOn: $audioEnabled)
                    .labelsHidden()
                    .tint(.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .tacticalPanel()
    }

    func sharePanel() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("settings.share".localized)

            ShareLink(item: shareURL, subject: Text("TriviaGOAT"), message: Text(shareText)) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 18))

                    Text("SHARE TRIVIAGOAT")
                        .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))

                    Spacer()
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange))
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    HapticManager.instance.successPulse()
                    playSettingsTap()
                }
            )
            .buttonStyle(.plain)

            Button {
                HapticManager.instance.rigidClick()
                playSettingsTap()
                ReviewPrompter.requestReview()
            } label: {
                HStack {
                    Image(systemName: "star.fill")
                        .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 18))

                    Text("RATE THIS APP")
                        .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))

                    Spacer()
                }
                .foregroundColor(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.10)))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .tacticalPanel()
    }

    func legalSupportPanel() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("settings.help_legal".localized)

            Link(destination: supportURL) {
                rowButton(title: "SUPPORT", systemImage: "lifepreserver.fill")
            }

            Link(destination: privacyURL) {
                rowButton(title: "PRIVACY POLICY", systemImage: "hand.raised.fill")
            }

            Link(destination: termsURL) {
                rowButton(title: "TERMS OF SERVICE", systemImage: "doc.text.fill")
            }

            Text(appVersionString())
                .font(DS.Typography.font(11, weight: .semibold, design: .rounded, cappedAt: 14))
                .foregroundColor(.white.opacity(0.40))
                .padding(.top, 4)
        }
        .tacticalPanel()
    }

    func rowButton(title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .font(DS.Typography.font(14, weight: .black, design: .default, cappedAt: 18))

            Text(title)
                .font(DS.Typography.font(14, weight: .black, design: .rounded, cappedAt: 18))

            Spacer()

            Image(systemName: "chevron.right")
                .font(DS.Typography.font(12, weight: .black, design: .default, cappedAt: 14))
                .foregroundColor(.white.opacity(0.55))
        }
        .foregroundColor(.white.opacity(0.92))
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    func rowInfoChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(DS.Typography.font(11, weight: .black, design: .default, cappedAt: 13))
                .foregroundColor(.orange.opacity(0.92))

            Text(title)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
                .foregroundColor(.white.opacity(0.84))
                .tracking(1.0)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
            .foregroundColor(.white.opacity(0.55))
            .tracking(2)
    }

    func resolvedCodename(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "UNCLAIMED PILOT" : cleaned
    }

    func footer(appRef: AppState) -> some View {
        Button {
            HapticManager.instance.impact(.light)
            playSettingsTap()

            appRef.saveProfile(
                name: appRef.profile.displayName,
                avatarStyle: selectedAvatarStyle,
                avatarSeed: selectedAvatarSeed
            )

            withAnimation(.spring()) {
                appRef.setRoute(.hq)
            }
        } label: {
            Text("settings.done".localized)
                .font(DS.Typography.font(16, weight: .black, design: .rounded, cappedAt: 20))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(ChunkyButtonStyle(color: Color.white.opacity(0.18)))
    }
}

// MARK: - Avatar View

private struct AvatarBadgeView: View {
    let url: URL?
    let fallbackSymbol: String
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: size - 12, height: size - 12)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    case .empty:
                        ProgressView()
                            .tint(.orange)

                    case .failure:
                        fallbackIcon

                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: fallbackSymbol)
            .font(.system(size: max(18, size * 0.34), weight: .black))
            .foregroundColor(.orange.opacity(0.92))
    }
}

// MARK: - Local View Helpers

private extension View {
    func panelInset() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}
