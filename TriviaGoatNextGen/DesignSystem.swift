//
//  DesignSystem.swift
//  TriviaGoatNextGen
//
//  Single source of truth for UI tokens + shared components.
//  Namespace: DS
//

import SwiftUI
import UIKit
import CoreMotion
import Combine

// ✅ Keep DS shorthand everywhere
typealias DS = DesignSystem

// MARK: - DS (Design System)

enum DesignSystem {

    // MARK: - Tokens

    enum T {
        static let cardRadius: CGFloat = 22
        static let panelRadius: CGFloat = 22
        static let strokeWidth: CGFloat = 1.5

        static let padXS: CGFloat = 8
        static let padS: CGFloat = 12
        static let padM: CGFloat = 16
        static let padL: CGFloat = 20
        static let padXL: CGFloat = 25

        static let buttonCorner: CGFloat = 16
        static let buttonDepth: CGFloat = 4
    }

    enum ColorToken {
        static let accent: Color = .orange
        static let bgBlack: Color = .black
        static let panelFill: Color = Color.black.opacity(0.85)
        static let panelStroke: Color = Color.white.opacity(0.15)
        static let softWhite: Color = Color.white.opacity(0.08)
    }

    // MARK: - Readability / Global Font Scaling

    enum TextScale: String, CaseIterable, Codable {
        case standard
        case large
        case extraLarge

        var title: String {
            switch self {
            case .standard:   return "Standard"
            case .large:      return "Large"
            case .extraLarge: return "Extra Large"
            }
        }

        var multiplier: CGFloat {
            switch self {
            case .standard:   return 1.00
            case .large:      return 1.10
            case .extraLarge: return 1.20
            }
        }
    }

    @MainActor
    final class ReadabilityManager: ObservableObject {
        static let shared = ReadabilityManager()

        private let storageKey = "tg.readability.textScale.v1"

        @Published var textScale: TextScale {
            didSet {
                UserDefaults.standard.set(textScale.rawValue, forKey: storageKey)
            }
        }

        private init() {
            let raw = UserDefaults.standard.string(forKey: storageKey) ?? TextScale.standard.rawValue
            self.textScale = TextScale(rawValue: raw) ?? .standard
        }

        var multiplier: CGFloat {
            textScale.multiplier
        }

        func setScale(_ scale: TextScale) {
            guard textScale != scale else { return }
            textScale = scale
        }

        func cycleForward() {
            let all = TextScale.allCases
            guard let idx = all.firstIndex(of: textScale) else {
                textScale = .standard
                return
            }
            textScale = all[(idx + 1) % all.count]
        }
    }

    enum Typography {

        static func scaled(_ size: CGFloat, cappedAt maxSize: CGFloat? = nil) -> CGFloat {
            let scaled = size * ReadabilityManager.shared.multiplier
            if let maxSize {
                return min(maxSize, scaled)
            }
            return scaled
        }

        static func safeScaled(_ size: CGFloat, min minSize: CGFloat, max maxSize: CGFloat) -> CGFloat {
            min(max(size * ReadabilityManager.shared.multiplier, minSize), maxSize)
        }

        static func lineLimit(for nominalLineCount: Int) -> Int {
            max(1, nominalLineCount)
        }

        static func font(
            _ size: CGFloat,
            weight: Font.Weight = .regular,
            design: Font.Design = .default,
            cappedAt maxSize: CGFloat? = nil
        ) -> Font {
            .system(
                size: scaled(size, cappedAt: maxSize),
                weight: weight,
                design: design
            )
        }

        static func uiFont(
            _ size: CGFloat,
            weight: UIFont.Weight = .regular,
            textStyle: UIFont.TextStyle = .body,
            cappedAt maxSize: CGFloat? = nil
        ) -> UIFont {
            let resolved = scaled(size, cappedAt: maxSize)
            let base = UIFont.systemFont(ofSize: resolved, weight: weight)
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        }

        // Preset slots for shared adoption across the app
        static var hero: Font {
            font(28, weight: .black, design: .rounded, cappedAt: 34)
        }

        static var title: Font {
            font(22, weight: .black, design: .rounded, cappedAt: 28)
        }

        static var section: Font {
            font(18, weight: .black, design: .rounded, cappedAt: 22)
        }

        static var bodyStrong: Font {
            font(14, weight: .bold, design: .rounded, cappedAt: 18)
        }

        static var body: Font {
            font(13, weight: .semibold, design: .rounded, cappedAt: 17)
        }

        static var captionMono: Font {
            font(10, weight: .black, design: .monospaced, cappedAt: 13)
        }

        static var chip: Font {
            font(11, weight: .black, design: .monospaced, cappedAt: 14)
        }

        static var score: Font {
            font(28, weight: .black, design: .rounded, cappedAt: 34)
        }

        static var timer: Font {
            font(16, weight: .black, design: .rounded, cappedAt: 20)
        }
    }

    // MARK: - Motion (lifecycle safe)

    @MainActor
    final class MotionManager: ObservableObject {
        private let manager = CMMotionManager()

        @Published var roll: CGFloat = 0
        @Published var pitch: CGFloat = 0

        private var running = false

        func start() {
            guard !running else { return }
            guard manager.isDeviceMotionAvailable else { return }

            running = true
            manager.deviceMotionUpdateInterval = 1 / 60

            manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                self?.roll = CGFloat(data.attitude.roll)
                self?.pitch = CGFloat(data.attitude.pitch)
            }
        }

        func stop() {
            guard running else { return }
            running = false
            manager.stopDeviceMotionUpdates()
        }
    }

    // MARK: - Space Background

    struct SpaceBackground: View {
        @EnvironmentObject var motion: MotionManager

        public init() {}

        public var body: some View {
            ZStack {
                ColorToken.bgBlack.ignoresSafeArea()

                GeometryReader { geo in
                    ConvexArenaGrid(
                        spacing: 60,
                        color: ColorToken.accent.opacity(0.15),
                        velocity: 1.0
                    )
                    .offset(x: motion.roll * 20, y: motion.pitch * 20)
                    .frame(width: geo.size.width * 1.5, height: geo.size.height * 1.5)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
    }

    // MARK: - Convex Grid

    struct ConvexArenaGrid: View {
        let spacing: CGFloat
        let color: Color
        let velocity: Double

        var body: some View {
            Canvas { context, size in
                var path = Path()

                for x in stride(from: 0, through: size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                for y in stride(from: 0, through: size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }

                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
            .opacity(0.6)
            .animation(
                .linear(duration: 20 / max(0.1, velocity)).repeatForever(autoreverses: false),
                value: velocity
            )
        }
    }

    // MARK: - XP Volumetric Bar

    struct XPVolumetricBar: View {
        let progress: Double

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))

                    Capsule()
                        .fill(ColorToken.accent)
                        .frame(width: geo.size.width * max(0, min(1, progress)))
                        .animation(.easeOut(duration: 0.35), value: progress)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Chunky Button Style

    struct ChunkyButtonStyle: ButtonStyle {
        var color: Color = ColorToken.accent
        var cornerRadius: CGFloat = T.buttonCorner
        var depth: CGFloat = T.buttonDepth

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed

            return configuration.label
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(color.opacity(0.75))
                            .offset(y: depth)

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(color)
                            .offset(y: pressed ? depth : 0)

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            .offset(y: pressed ? depth : 0)
                    }
                )
                .animation(.spring(response: 0.18, dampingFraction: 0.75), value: pressed)
        }
    }
}

// MARK: - Global convenience aliases

typealias MotionManager = DS.MotionManager
typealias XPVolumetricBar = DS.XPVolumetricBar
typealias ChunkyButtonStyle = DS.ChunkyButtonStyle
typealias ReadabilityManager = DS.ReadabilityManager

// MARK: - View Modifiers (4D Glass + Readability Helpers)

extension View {

    func glassCard(
        cornerRadius: CGFloat = 20,
        fillOpacity: Double = 0.92,
        shadowOpacity: Double = 0.06
    ) -> some View {
        self
            .padding()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
                    .shadow(color: Color.black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }

    func tacticalPanel(
        cornerRadius: CGFloat = 22,
        strokeOpacity: Double = 0.15,
        shadowOpacity: Double = 0.06
    ) -> some View {
        self
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.85))
                    .shadow(color: Color.black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1.5)
            )
    }
}

extension Text {
    func dsBody() -> some View {
        self.font(DS.Typography.body)
    }

    func dsBodyStrong() -> some View {
        self.font(DS.Typography.bodyStrong)
    }

    func dsSection() -> some View {
        self.font(DS.Typography.section)
    }

    func dsHero() -> some View {
        self.font(DS.Typography.hero)
    }

    func dsCaptionMono() -> some View {
        self.font(DS.Typography.captionMono)
    }

    func dsChip() -> some View {
        self.font(DS.Typography.chip)
    }

    func dsScore() -> some View {
        self.font(DS.Typography.score)
    }

    func dsTimer() -> some View {
        self.font(DS.Typography.timer)
    }
}
