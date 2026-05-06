//
//  BattleDecisionView.swift
//  TriviaGoatNextGen
//
//  Contextual post-battle decision landing
//

import SwiftUI

struct BattleDecisionView: View {
    enum Outcome: Equatable {
        case victory
        case defeat
        case draw
    }

    enum Context: Equatable {
        case duel
        case tribe
        case solo
    }

    let context: Context
    let outcome: Outcome
    let opponentName: String
    let scoreLine: String

    let onRematch: () -> Void
    let onDailyMission: () -> Void
    let onTraining: () -> Void
    let onBackToHQ: () -> Void

    @State private var glow = false
    @State private var pulse = false
    @State private var mascotFloat = false
    @State private var ringSpin = false

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            ZStack {
                SpaceBackground()
                backgroundWash

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Color.clear.frame(height: max(14, safeTop + 4))

                        heroPanel

                        if context != .solo {
                            actionStack
                        } else {
                            soloCommandBar
                        }

                        Color.clear.frame(height: max(20, safeBottom + 10))
                    }
                    .padding(.horizontal, 16)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarHidden(true)
        .onAppear { startMotion() }
    }

    private func startMotion() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            glow.toggle()
        }

        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulse.toggle()
        }

        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            mascotFloat.toggle()
        }

        withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) {
            ringSpin.toggle()
        }
    }
}

// MARK: - Premium Layout

private extension BattleDecisionView {

    var backgroundWash: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.44),
                    Color.black.opacity(0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    haloColor.opacity(glow ? 0.20 : 0.10),
                    Color.orange.opacity(glow ? 0.045 : 0.02),
                    Color.clear
                ],
                center: .top,
                startRadius: 16,
                endRadius: 430
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.00),
                    Color.white.opacity(0.025),
                    Color.white.opacity(0.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    var heroPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            topHeroRow
            outcomeSummaryCard

            if context != .solo {
                tacticalDetails
                momentumBand
                Text(footerSupportText)
                    .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                    .foregroundColor(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(haloColor.opacity(glow ? 0.28 : 0.10), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.42), radius: 28, x: 0, y: 18)
        .shadow(color: haloColor.opacity(glow ? 0.08 : 0.03), radius: 24, x: 0, y: 12)
    }

    var topHeroRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                mascotHero
                heroTextBlock
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    mascotHero
                    Spacer(minLength: 0)
                }

                heroTextBlock
            }
        }
    }

    var heroTextBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerEyebrow)
                .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                .foregroundColor(.orange.opacity(0.96))
                .tracking(2.2)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(resultHeroText)
                .font(DS.Typography.font(28, weight: .black, design: .rounded, cappedAt: 36))
                .foregroundColor(.white.opacity(0.98))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)

            Text(resultSupportText)
                .font(DS.Typography.font(14, weight: .bold, design: .rounded, cappedAt: 18))
                .foregroundColor(.white.opacity(0.70))
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    var mascotHero: some View {
        ZStack {
            Circle()
                .fill(haloColor.opacity(glow ? 0.24 : 0.11))
                .frame(width: glow ? 112 : 98, height: glow ? 112 : 98)
                .blur(radius: glow ? 18 : 10)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            haloColor.opacity(0.10),
                            haloColor.opacity(0.58),
                            Color.white.opacity(0.10),
                            haloColor.opacity(0.10)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.25, dash: [4, 7])
                )
                .frame(width: 104, height: 104)
                .rotationEffect(.degrees(ringSpin ? 360 : 0))

            Circle()
                .fill(Color.white.opacity(0.055))
                .frame(width: 88, height: 88)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.11), lineWidth: 1)
                )

            Image("goat_icon")
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 78)
                .offset(y: mascotFloat ? -2 : 2)
        }
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)
    }

    var outcomeSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(primaryChipTitle)
                    .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 13))
                    .foregroundColor(.white.opacity(0.46))
                    .tracking(1.6)

                Spacer()

                Text(primaryChipValue)
                    .font(DS.Typography.font(11, weight: .black, design: .monospaced, cappedAt: 14))
                    .foregroundColor(haloColor.opacity(0.96))
                    .tracking(1.1)
            }

            Text(firstStatValue)
                .font(DS.Typography.font(context == .solo ? 22 : 18, weight: .black, design: .rounded, cappedAt: context == .solo ? 30 : 24))
                .foregroundColor(.white.opacity(0.96))
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)

            if context == .solo {
                Text(normalizedScoreLine)
                    .font(DS.Typography.font(15, weight: .black, design: .rounded, cappedAt: 20))
                    .foregroundColor(.orange.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(secondStatValue)
                    .font(DS.Typography.font(13, weight: .bold, design: .rounded, cappedAt: 17))
                    .foregroundColor(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(haloColor.opacity(0.18), lineWidth: 1)
        )
    }

    var tacticalDetails: some View {
        VStack(spacing: 10) {
            detailRow(label: secondStatLabel, value: secondStatValue)
            detailRow(label: "DETAIL", value: normalizedScoreLine)

            if shouldShowOpponentChip {
                detailRow(label: secondaryChipTitle, value: secondaryChipValue)
            }
        }
    }

    func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(DS.Typography.font(9, weight: .black, design: .monospaced, cappedAt: 11))
                .foregroundColor(.white.opacity(0.44))
                .tracking(1.2)

            Text(value)
                .font(DS.Typography.font(13, weight: .black, design: .rounded, cappedAt: 17))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(4)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var momentumBand: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                badge(text: outcomeBadgeText, tint: haloColor)
                badge(text: contextBadgeText, tint: .white)
            }

            VStack(alignment: .leading, spacing: 8) {
                badge(text: outcomeBadgeText, tint: haloColor)
                badge(text: contextBadgeText, tint: .white)
            }
        }
    }

    func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(DS.Typography.font(10, weight: .black, design: .monospaced, cappedAt: 12))
            .foregroundColor(.white.opacity(0.90))
            .tracking(1.0)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(tint.opacity(0.20), lineWidth: 1))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }

    var soloCommandBar: some View {
        VStack(spacing: 12) {
            Text("Choose your next move.")
                .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                .foregroundColor(.white.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            primaryActionButton(
                title: soloPrimaryTitle,
                subtitle: soloPrimarySubtitle,
                icon: soloPrimaryIcon,
                fill: .orange,
                foreground: .black,
                pulse: pulse,
                action: soloPrimaryAction
            )

            actionButton(
                title: "BACK TO HQ",
                subtitle: "Return to Arena command",
                icon: "house.fill",
                action: onBackToHQ
            )
        }
    }

    var actionStack: some View {
        VStack(spacing: 12) {
            if context == .duel {
                primaryActionButton(
                    title: "SEND REMATCH",
                    subtitle: rematchSubtitle,
                    icon: "arrow.clockwise",
                    fill: Color.white,
                    foreground: .black,
                    pulse: pulse,
                    action: onRematch
                )
            }

            switch context {
            case .duel:
                actionButton(
                    title: "DAILY MISSION",
                    subtitle: "Bank progress with today’s curated run",
                    icon: "flag.checkered",
                    action: onDailyMission
                )

                actionButton(
                    title: "TRAINING",
                    subtitle: "Sharpen up before the next clash",
                    icon: "dumbbell.fill",
                    action: onTraining
                )

                actionButton(
                    title: "BACK TO HQ",
                    subtitle: "Return to Arena command",
                    icon: "house.fill",
                    action: onBackToHQ
                )

            case .tribe:
                primaryActionButton(
                    title: tribePrimaryTitle,
                    subtitle: tribePrimarySubtitle,
                    icon: tribePrimaryIcon,
                    fill: Color.white,
                    foreground: .black,
                    pulse: pulse,
                    action: onBackToHQ
                )

                actionButton(
                    title: "DAILY MISSION",
                    subtitle: "Bank solo progress after the tribe clash",
                    icon: "flag.checkered",
                    action: onDailyMission
                )

                actionButton(
                    title: "TRAINING",
                    subtitle: "Sharpen up before the next ladder run",
                    icon: "dumbbell.fill",
                    action: onTraining
                )

            case .solo:
                EmptyView()
            }
        }
    }

    func primaryActionButton(
        title: String,
        subtitle: String,
        icon: String,
        fill: Color,
        foreground: Color,
        pulse: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.10))
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(DS.Typography.font(16, weight: .black, design: .default, cappedAt: 19))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DS.Typography.font(13, weight: .black, design: .monospaced, cappedAt: 16))
                        .tracking(1.0)

                    Text(subtitle)
                        .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                        .foregroundColor(foreground.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(DS.Typography.font(13, weight: .black, design: .default, cappedAt: 15))
                    .opacity(0.55)
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(pulse ? 0.24 : 0.10), lineWidth: 1)
            )
            .scaleEffect(pulse ? 1.004 : 1.0)
        }
        .buttonStyle(BattleDecisionPressScaleStyle())
    }

    func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(DS.Typography.font(16, weight: .black, design: .default, cappedAt: 19))
                        .foregroundColor(.orange.opacity(0.95))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DS.Typography.font(13, weight: .black, design: .monospaced, cappedAt: 16))
                        .foregroundColor(.white)
                        .tracking(1.0)

                    Text(subtitle)
                        .font(DS.Typography.font(12, weight: .semibold, design: .rounded, cappedAt: 16))
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.26))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(BattleDecisionPressScaleStyle())
    }
}

// MARK: - Copy / State

private extension BattleDecisionView {

    var resolvedOpponentName: String {
        let cleaned = opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "RIVAL PILOT" : cleaned
    }

    var normalizedScoreLine: String {
        let cleaned = scoreLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "MATCH COMPLETE" : cleaned
    }

    var haloColor: Color {
        switch outcome {
        case .victory: return .orange
        case .defeat: return context == .solo ? .orange : .white
        case .draw: return .orange
        }
    }

    var headerEyebrow: String {
        switch context {
        case .duel: return "DUEL RESULT"
        case .tribe: return "TRIBE RESULT"
        case .solo: return "RUN RESULT"
        }
    }

    var resultHeroText: String {
        switch context {
        case .duel:
            switch outcome {
            case .victory: return "RIVAL CHECKED"
            case .defeat: return "RIVAL GOT YOU"
            case .draw: return "NO CLEAR WINNER"
            }

        case .tribe:
            switch outcome {
            case .victory: return "LAST PILOT STANDING"
            case .defeat: return "YOU WERE ELIMINATED"
            case .draw: return "TRIBE STANDOFF"
            }

        case .solo:
            switch outcome {
            case .victory: return "RUN COMPLETE"
            case .defeat: return "RESET AND GO AGAIN"
            case .draw: return "SOLID FINISH"
            }
        }
    }

    var resultSupportText: String {
        switch context {
        case .duel:
            switch outcome {
            case .victory: return "You held the line and left no debate."
            case .defeat: return "They got this one. Send it right back."
            case .draw: return "No separation. Settle it in the rematch."
            }

        case .tribe:
            switch outcome {
            case .victory: return "You outlasted the field. The ladder knows your name."
            case .defeat: return "The tribe battle moved on without you. Come back sharper."
            case .draw: return "No clean champion energy here. The next run decides it."
            }

        case .solo:
            switch outcome {
            case .victory: return "Progress banked. Keep the momentum alive."
            case .defeat: return "One clean reset puts you right back in rhythm."
            case .draw: return "Progress banked. Keep building."
            }
        }
    }

    var primaryChipTitle: String {
        switch context {
        case .duel: return "RESULT"
        case .tribe: return "STATUS"
        case .solo: return "STATUS"
        }
    }

    var primaryChipValue: String {
        switch context {
        case .duel:
            switch outcome {
            case .victory: return "VICTORY"
            case .defeat: return "DEFEAT"
            case .draw: return "DRAW"
            }

        case .tribe:
            switch outcome {
            case .victory: return "CHAMPION"
            case .defeat: return "ELIMINATED"
            case .draw: return "STANDOFF"
            }

        case .solo:
            switch outcome {
            case .victory: return "COMPLETE"
            case .defeat: return "RESET MODE"
            case .draw: return "COMPLETE"
            }
        }
    }

    var shouldShowOpponentChip: Bool {
        context == .duel
    }

    var secondaryChipTitle: String {
        "OPPONENT"
    }

    var secondaryChipValue: String {
        resolvedOpponentName
    }

    var firstStatLabel: String {
        switch context {
        case .duel: return "WINNER"
        case .tribe: return "VERDICT"
        case .solo: return "NEXT"
        }
    }

    var firstStatValue: String {
        switch context {
        case .duel:
            switch outcome {
            case .victory: return "YOU"
            case .defeat: return resolvedOpponentName
            case .draw: return "NO DECISIVE WINNER"
            }

        case .tribe:
            switch outcome {
            case .victory: return "YOU STOOD LAST"
            case .defeat: return "FIELD ADVANCED"
            case .draw: return "ALL SURVIVED"
            }

        case .solo:
            switch outcome {
            case .victory: return "Bank the win, protect the streak, and keep climbing."
            case .defeat: return "Reset fast and stack a cleaner run."
            case .draw: return "One more run builds the heat."
            }
        }
    }

    var secondStatLabel: String {
        switch context {
        case .duel: return "MATCH"
        case .tribe: return "BATTLE"
        case .solo: return "NEXT"
        }
    }

    var secondStatValue: String {
        switch context {
        case .duel:
            switch outcome {
            case .victory: return "YOU PUT \(resolvedOpponentName.uppercased()) ON NOTICE"
            case .defeat: return "\(resolvedOpponentName.uppercased()) TOOK THIS ROUND"
            case .draw: return "THIS RIVALRY NEEDS A DECIDER"
            }

        case .tribe:
            switch outcome {
            case .victory: return "THE GOAT OF THIS LOBBY WAS YOU"
            case .defeat: return "THE LOBBY GOT ITS CHAMPION"
            case .draw: return "NO PILOT DROPPED THIS ROUND"
            }

        case .solo:
            switch outcome {
            case .victory: return "KEEP PUSHING WITH DAILY MISSION OR TRAINING"
            case .defeat: return "RESET FAST AND STACK A CLEANER RUN"
            case .draw: return "ONE MORE RUN BUILDS THE HEAT"
            }
        }
    }

    var outcomeBadgeText: String {
        switch context {
        case .duel:
            switch outcome {
            case .victory: return "RIVAL CRUSHED"
            case .defeat: return "ANSWER BACK"
            case .draw: return "DECIDER READY"
            }

        case .tribe:
            switch outcome {
            case .victory: return "CROWN CLAIMED"
            case .defeat: return "COME BACK HARDER"
            case .draw: return "NO ELIMINATION"
            }

        case .solo:
            switch outcome {
            case .victory: return "MOMENTUM UP"
            case .defeat: return "RESET MODE"
            case .draw: return "KEEP GOING"
            }
        }
    }

    var contextBadgeText: String {
        switch context {
        case .duel: return "DUEL FLOW"
        case .tribe: return "TRIBE LADDER"
        case .solo: return "SOLO RUN"
        }
    }

    var rematchSubtitle: String {
        switch outcome {
        case .victory: return "Push the advantage while they still feel it"
        case .defeat: return "Send the rematch now and answer back immediately"
        case .draw: return "Settle it now with a clean decider"
        }
    }

    var tribePrimaryTitle: String {
        "RETURN TO HQ"
    }

    var tribePrimarySubtitle: String {
        switch outcome {
        case .victory: return "Leave as champion and queue the next move"
        case .defeat: return "Reset, regroup, and re-enter stronger"
        case .draw: return "Reset the field and run it back from command"
        }
    }

    var tribePrimaryIcon: String {
        switch outcome {
        case .victory: return "crown.fill"
        case .defeat, .draw: return "house.fill"
        }
    }

    var soloPrimaryTitle: String {
        switch outcome {
        case .victory: return "DAILY MISSION"
        case .defeat: return "RUN IT BACK"
        case .draw: return "DAILY MISSION"
        }
    }

    var soloPrimarySubtitle: String {
        switch outcome {
        case .victory: return "Jump into the next curated challenge"
        case .defeat: return "Reset now and build a cleaner run"
        case .draw: return "Keep the momentum moving"
        }
    }

    var soloPrimaryIcon: String {
        switch outcome {
        case .victory, .draw: return "flag.checkered"
        case .defeat: return "arrow.clockwise"
        }
    }

    var soloPrimaryAction: () -> Void {
        switch outcome {
        case .victory, .draw:
            return onDailyMission
        case .defeat:
            return onTraining
        }
    }

    var footerSupportText: String {
        switch context {
        case .duel:
            return "Lock the rematch, bank the mission, or sharpen up and queue another clash."
        case .tribe:
            return "Champion or not, regroup fast and choose the next ladder move."
        case .solo:
            return "Bank progress, keep the streak alive, and roll straight into the next run."
        }
    }
}

// MARK: - Button Style

private struct BattleDecisionPressScaleStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.985
    var pressedOpacity: Double = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
