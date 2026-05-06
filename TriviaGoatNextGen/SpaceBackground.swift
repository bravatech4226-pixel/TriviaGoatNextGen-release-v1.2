//
//  SpaceBackground.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-03-04.
//
//

import SwiftUI

struct SpaceBackground: View {

    enum MotionMode {
        case staticPremium
        case cinematic
    }

    var motionMode: MotionMode = .staticPremium

    private var allowsMotion: Bool {
        motionMode == .cinematic && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    // MARK: - Tunables

    var showsGrid: Bool = false
    var gridSpacing: CGFloat = 52
    var gridOpacity: Double = 0.020
    var vignetteOpacity: Double = 0.54

    // MARK: - Motion

    @State private var farDrift: Bool = false
    @State private var midDrift: Bool = false
    @State private var nearDrift: Bool = false
    @State private var bandPulse: Bool = false
    @State private var atmospherePulse: Bool = false
    @State private var orbitShift: Bool = false
    @State private var dustShift: Bool = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let maxSide = max(size.width, size.height)
            let minSide = min(size.width, size.height)

            ZStack {
                baseVoid

                GalacticBandLayer(
                    size: size,
                    pulse: bandPulse,
                    dustShift: dustShift
                )
                .ignoresSafeArea()

                NebulaBloomLayer(
                    size: size,
                    pulse: bandPulse
                )
                .ignoresSafeArea()

                StarfieldLayer(
                    stars: StarSeed.farField,
                    canvasSize: size,
                    xShift: farDrift ? 6 : -4,
                    yShift: farDrift ? 4 : -3,
                    opacity: 0.28
                )
                .ignoresSafeArea()

                StarfieldLayer(
                    stars: StarSeed.midField,
                    canvasSize: size,
                    xShift: midDrift ? 12 : -8,
                    yShift: midDrift ? 8 : -5,
                    opacity: 0.54
                )
                .ignoresSafeArea()

                if allowsMotion {
                    StarfieldLayer(
                        stars: StarSeed.nearField,
                        canvasSize: size,
                        xShift: nearDrift ? 18 : -12,
                        yShift: nearDrift ? 12 : -8,
                        opacity: 0.72
                    )
                    .ignoresSafeArea()
                }

                // Primary planet pushed up and made much more visible
                PlanetLimbLayer(
                    diameter: maxSide * 1.30,
                    atmospherePulse: atmospherePulse
                )
                .offset(x: -maxSide * 0.28, y: maxSide * 0.39)
                .ignoresSafeArea()

                PlanetShadowContour(
                    diameter: maxSide * 1.18
                )
                .offset(x: -maxSide * 0.20, y: maxSide * 0.33)
                .ignoresSafeArea()

                // Secondary planet made larger and more readable
                if allowsMotion {
                    SecondaryPlanetLayer(
                        diameter: minSide * 0.32,
                        atmospherePulse: atmospherePulse
                    )
                    .offset(x: maxSide * 0.23, y: -maxSide * 0.10)
                    .ignoresSafeArea()
                }

                OrbitalArcLayer(
                    size: size,
                    orbitShift: orbitShift
                )
                .ignoresSafeArea()

                if showsGrid {
                    GridOverlay(spacing: gridSpacing)
                        .opacity(gridOpacity)
                        .ignoresSafeArea()
                }

                ForegroundHazeLayer(
                    size: size,
                    atmospherePulse: atmospherePulse
                )
                .ignoresSafeArea()

                vignette
                    .ignoresSafeArea()
            }
            .compositingGroup()
            .onAppear {
                guard allowsMotion else {
                    farDrift = false
                    midDrift = false
                    nearDrift = false
                    bandPulse = false
                    atmospherePulse = false
                    orbitShift = false
                    dustShift = false
                    return
                }

                withAnimation(.easeInOut(duration: 36).repeatForever(autoreverses: true)) {
                    farDrift.toggle()
                }

                withAnimation(.easeInOut(duration: 30).repeatForever(autoreverses: true)) {
                    midDrift.toggle()
                }

                withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) {
                    nearDrift.toggle()
                }

                withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                    bandPulse.toggle()
                }

                withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                    atmospherePulse.toggle()
                }

                withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
                    orbitShift.toggle()
                }

                withAnimation(.easeInOut(duration: 32).repeatForever(autoreverses: true)) {
                    dustShift.toggle()
                }
            }
        }
    }

    // MARK: - Foundation Layers

    private var baseVoid: some View {
        ZStack {
            Color.black

            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.18, green: 0.12, blue: 0.30).opacity(0.10),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(red: 0.06, green: 0.16, blue: 0.26).opacity(0.08),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 540
            )
        }
    }

    private var vignette: some View {
        RadialGradient(
            colors: [
                Color.clear,
                Color.black.opacity(vignetteOpacity)
            ],
            center: .center,
            startRadius: 180,
            endRadius: 900
        )
    }
}

// MARK: - Galactic Band

private struct GalacticBandLayer: View {
    let size: CGSize
    let pulse: Bool
    let dustShift: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.95, green: 0.58, blue: 0.20).opacity(pulse ? 0.12 : 0.07),
                            Color(red: 0.46, green: 0.34, blue: 0.88).opacity(pulse ? 0.10 : 0.055),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size.width * 1.68, height: size.height * 0.34)
                .blur(radius: pulse ? 26 : 20)
                .rotationEffect(.degrees(-16))
                .offset(
                    x: dustShift ? -size.width * 0.012 : size.width * 0.012,
                    y: -size.height * 0.025
                )

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.060),
                            Color.orange.opacity(0.020),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size.width * 1.32, height: size.height * 0.15)
                .blur(radius: 11)
                .rotationEffect(.degrees(-17))
                .offset(
                    x: dustShift ? size.width * 0.016 : -size.width * 0.016,
                    y: -size.height * 0.035
                )
        }
       
    }
}

private struct NebulaBloomLayer: View {
    let size: CGSize
    let pulse: Bool

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.white.opacity(pulse ? 0.060 : 0.034),
                    Color.orange.opacity(pulse ? 0.042 : 0.024),
                    Color.clear
                ],
                center: .center,
                startRadius: 4,
                endRadius: 300
            )
            .frame(width: 540, height: 540)
            .offset(x: size.width * 0.02, y: -size.height * 0.05)

            RadialGradient(
                colors: [
                    Color.purple.opacity(pulse ? 0.070 : 0.042),
                    Color.clear
                ],
                center: .center,
                startRadius: 6,
                endRadius: 270
            )
            .frame(width: 430, height: 430)
            .offset(x: -size.width * 0.18, y: size.height * 0.18)

            RadialGradient(
                colors: [
                    Color.blue.opacity(0.040),
                    Color.clear
                ],
                center: .center,
                startRadius: 6,
                endRadius: 250
            )
            .frame(width: 380, height: 380)
            .offset(x: size.width * 0.28, y: size.height * 0.30)
        }
    }
}

// MARK: - Planet Layers

private struct PlanetLimbLayer: View {
    let diameter: CGFloat
    let atmospherePulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.16, green: 0.21, blue: 0.31),
                            Color(red: 0.05, green: 0.07, blue: 0.12),
                            Color.black
                        ],
                        center: .center,
                        startRadius: diameter * 0.02,
                        endRadius: diameter * 0.55
                    )
                )
                .frame(width: diameter, height: diameter)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(atmospherePulse ? 0.48 : 0.28),
                            Color.white.opacity(atmospherePulse ? 0.30 : 0.16),
                            Color.blue.opacity(atmospherePulse ? 0.24 : 0.12),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: atmospherePulse ? 7 : 4.5
                )
                .frame(width: diameter, height: diameter)
                .blur(radius: atmospherePulse ? 4.8 : 2.8)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1.0)
                .frame(width: diameter * 0.995, height: diameter * 0.995)

            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color.clear,
                            Color.orange.opacity(0.08),
                            Color.clear,
                            Color.purple.opacity(0.06),
                            Color.clear,
                            Color.blue.opacity(0.05),
                            Color.clear
                        ],
                        center: .center
                    )
                )
                .frame(width: diameter * 0.985, height: diameter * 0.985)
                .blur(radius: 16)
        }
        .opacity(0.995)
    }
}

private struct PlanetShadowContour: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .stroke(Color.black.opacity(0.36), lineWidth: 24)
            .frame(width: diameter, height: diameter)
            .blur(radius: 18)
            .mask(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black,
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct SecondaryPlanetLayer: View {
    let diameter: CGFloat
    let atmospherePulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.34, green: 0.24, blue: 0.56),
                            Color(red: 0.11, green: 0.10, blue: 0.17),
                            Color.black
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: diameter * 0.56
                    )
                )
                .frame(width: diameter, height: diameter)

            Circle()
                .stroke(Color.white.opacity(0.20), lineWidth: 1.2)
                .frame(width: diameter, height: diameter)

            Circle()
                .stroke(Color.orange.opacity(atmospherePulse ? 0.28 : 0.14), lineWidth: 3.2)
                .frame(width: diameter * 1.03, height: diameter * 1.03)
                .blur(radius: 2.4)

            Circle()
                .fill(Color.orange.opacity(atmospherePulse ? 0.16 : 0.09))
                .frame(width: diameter * 1.24, height: diameter * 1.24)
                .blur(radius: 22)
        }
        .shadow(color: .black.opacity(0.44), radius: 24, x: 0, y: 18)
    }
}

// MARK: - Orbital Infrastructure

private struct OrbitalArcLayer: View {
    let size: CGSize
    let orbitShift: Bool

    var body: some View {
        ZStack {
            OrbitalArcShape(
                rect: CGRect(
                    x: -size.width * 0.22,
                    y: size.height * 0.08,
                    width: size.width * 1.40,
                    height: size.height * 0.66
                )
            )
            .stroke(
                Color.white.opacity(0.035),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
            )

            OrbitalArcShape(
                rect: CGRect(
                    x: -size.width * 0.08,
                    y: size.height * 0.02,
                    width: size.width * 1.14,
                    height: size.height * 0.50
                )
            )
            .stroke(
                Color.orange.opacity(orbitShift ? 0.09 : 0.05),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [5, 8])
            )

            OrbitalArcShape(
                rect: CGRect(
                    x: size.width * 0.12,
                    y: size.height * 0.26,
                    width: size.width * 0.90,
                    height: size.height * 0.34
                )
            )
            .stroke(
                Color.purple.opacity(0.05),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [2, 7])
            )

            Circle()
                .fill(Color.white.opacity(orbitShift ? 0.13 : 0.06))
                .frame(width: 4, height: 4)
                .offset(x: size.width * 0.20, y: size.height * 0.05)
                .blur(radius: orbitShift ? 0.2 : 0.0)

            Circle()
                .fill(Color.orange.opacity(orbitShift ? 0.13 : 0.06))
                .frame(width: 5, height: 5)
                .offset(x: -size.width * 0.12, y: size.height * 0.16)
                .blur(radius: orbitShift ? 0.3 : 0.0)
        }
    }
}

private struct OrbitalArcShape: Shape {
    let rect: CGRect

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width * 0.5,
            startAngle: .degrees(208),
            endAngle: .degrees(336),
            clockwise: false
        )
        return path
    }
}

// MARK: - Foreground Haze

private struct ForegroundHazeLayer: View {
    let size: CGSize
    let atmospherePulse: Bool

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.orange.opacity(atmospherePulse ? 0.12 : 0.08),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: max(size.width, size.height) * 0.48
            )
            .offset(x: -size.width * 0.18, y: size.height * 0.20)

            RadialGradient(
                colors: [
                    Color.purple.opacity(0.10),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: max(size.width, size.height) * 0.40
            )
            .offset(x: size.width * 0.16, y: -size.height * 0.14)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.010),
                    Color.clear,
                    Color.black.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Starfield

private struct StarfieldLayer: View {
    let stars: [StarSeed]
    let canvasSize: CGSize
    let xShift: CGFloat
    let yShift: CGFloat
    let opacity: Double

    var body: some View {
        ZStack {
            ForEach(stars) { star in
                StarNode(
                    star: star,
                    canvasSize: canvasSize,
                    xShift: xShift,
                    yShift: yShift
                )
            }
        }
        .opacity(opacity)
    }
}

private struct StarNode: View {
    let star: StarSeed
    let canvasSize: CGSize
    let xShift: CGFloat
    let yShift: CGFloat

    private var baseX: CGFloat { canvasSize.width * star.x }
    private var baseY: CGFloat { canvasSize.height * star.y }

    var body: some View {
        ZStack {
            Circle()
                .fill(star.color.opacity(star.opacity))
                .frame(width: star.size, height: star.size)

            // Glow intentionally removed for idle power savings.
        }
        .position(
            x: baseX + (star.driftX * xShift / 18),
            y: baseY + (star.driftY * yShift / 12)
        )
        .blendMode(.screen)
    }
}

// MARK: - Star Data

private struct StarSeed: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
    let glow: Double
    let driftX: CGFloat
    let driftY: CGFloat
    let color: Color

    static let farField: [StarSeed] = [
        .init(id: 1,  x: 0.08, y: 0.12, size: 1.0, opacity: 0.42, glow: 0.00, driftX: 1.0,  driftY: 0.8,  color: .white),
        .init(id: 2,  x: 0.16, y: 0.24, size: 1.1, opacity: 0.36, glow: 0.00, driftX: -0.8, driftY: 0.6,  color: .white),
        .init(id: 3,  x: 0.22, y: 0.10, size: 1.2, opacity: 0.44, glow: 0.00, driftX: 0.7,  driftY: -0.7, color: .orange),
        .init(id: 4,  x: 0.30, y: 0.18, size: 1.0, opacity: 0.40, glow: 0.00, driftX: -1.0, driftY: 0.4,  color: .white),
        .init(id: 5,  x: 0.42, y: 0.08, size: 1.1, opacity: 0.38, glow: 0.00, driftX: 1.1,  driftY: 0.5,  color: .white),
        .init(id: 6,  x: 0.56, y: 0.12, size: 1.0, opacity: 0.35, glow: 0.00, driftX: -0.9, driftY: -0.6, color: .purple),
        .init(id: 7,  x: 0.68, y: 0.20, size: 1.2, opacity: 0.44, glow: 0.00, driftX: 0.8,  driftY: 0.6,  color: .white),
        .init(id: 8,  x: 0.78, y: 0.14, size: 1.1, opacity: 0.40, glow: 0.00, driftX: -0.6, driftY: 0.3,  color: .white),
        .init(id: 9,  x: 0.90, y: 0.10, size: 1.0, opacity: 0.34, glow: 0.00, driftX: 0.7,  driftY: -0.2, color: .orange),
        .init(id: 10, x: 0.12, y: 0.42, size: 1.1, opacity: 0.36, glow: 0.00, driftX: 1.0,  driftY: -0.5, color: .white),
        .init(id: 11, x: 0.24, y: 0.36, size: 1.0, opacity: 0.38, glow: 0.00, driftX: -0.8, driftY: 0.4,  color: .white),
        .init(id: 12, x: 0.36, y: 0.30, size: 1.2, opacity: 0.46, glow: 0.00, driftX: 0.6,  driftY: 0.2,  color: .white),
        .init(id: 13, x: 0.48, y: 0.40, size: 1.0, opacity: 0.34, glow: 0.00, driftX: -0.6, driftY: -0.2, color: .purple),
        .init(id: 14, x: 0.60, y: 0.34, size: 1.1, opacity: 0.40, glow: 0.00, driftX: 0.8,  driftY: 0.4,  color: .white),
        .init(id: 15, x: 0.72, y: 0.38, size: 1.0, opacity: 0.36, glow: 0.00, driftX: -1.0, driftY: 0.3,  color: .white),
        .init(id: 16, x: 0.84, y: 0.32, size: 1.1, opacity: 0.38, glow: 0.00, driftX: 0.6,  driftY: -0.5, color: .orange),
        .init(id: 17, x: 0.94, y: 0.44, size: 1.0, opacity: 0.32, glow: 0.00, driftX: -0.4, driftY: 0.2,  color: .white),
        .init(id: 18, x: 0.06, y: 0.70, size: 1.0, opacity: 0.34, glow: 0.00, driftX: 0.7,  driftY: -0.3, color: .white),
        .init(id: 19, x: 0.18, y: 0.62, size: 1.2, opacity: 0.42, glow: 0.00, driftX: -0.9, driftY: 0.3,  color: .white),
        .init(id: 20, x: 0.32, y: 0.74, size: 1.1, opacity: 0.36, glow: 0.00, driftX: 1.0,  driftY: 0.4,  color: .purple),
        .init(id: 21, x: 0.46, y: 0.68, size: 1.0, opacity: 0.34, glow: 0.00, driftX: -0.6, driftY: -0.5, color: .white),
        .init(id: 22, x: 0.58, y: 0.82, size: 1.1, opacity: 0.38, glow: 0.00, driftX: 0.8,  driftY: 0.2,  color: .white),
        .init(id: 23, x: 0.72, y: 0.72, size: 1.0, opacity: 0.36, glow: 0.00, driftX: -1.0, driftY: 0.4,  color: .orange),
        .init(id: 24, x: 0.86, y: 0.78, size: 1.2, opacity: 0.40, glow: 0.00, driftX: 0.6,  driftY: -0.3, color: .white),
        .init(id: 25, x: 0.94, y: 0.66, size: 1.0, opacity: 0.32, glow: 0.00, driftX: -0.5, driftY: 0.3,  color: .white)
    ]

    static let midField: [StarSeed] = [
        .init(id: 101, x: 0.10, y: 0.18, size: 1.6, opacity: 0.60, glow: 0.04, driftX: 1.2,  driftY: 0.9,  color: .white),
        .init(id: 102, x: 0.20, y: 0.28, size: 1.8, opacity: 0.58, glow: 0.05, driftX: -1.1, driftY: 0.7,  color: .orange),
        .init(id: 103, x: 0.28, y: 0.16, size: 1.7, opacity: 0.56, glow: 0.04, driftX: 0.9,  driftY: -0.8, color: .white),
        .init(id: 104, x: 0.40, y: 0.24, size: 1.9, opacity: 0.64, glow: 0.05, driftX: -1.2, driftY: 0.5,  color: .white),
        .init(id: 105, x: 0.54, y: 0.14, size: 1.7, opacity: 0.55, glow: 0.04, driftX: 1.0,  driftY: 0.7,  color: .purple),
        .init(id: 106, x: 0.64, y: 0.20, size: 1.8, opacity: 0.62, glow: 0.05, driftX: -0.9, driftY: -0.7, color: .white),
        .init(id: 107, x: 0.78, y: 0.12, size: 1.6, opacity: 0.58, glow: 0.04, driftX: 1.2,  driftY: 0.5,  color: .white),
        .init(id: 108, x: 0.88, y: 0.26, size: 1.9, opacity: 0.60, glow: 0.05, driftX: -1.1, driftY: 0.9,  color: .orange),
        .init(id: 109, x: 0.14, y: 0.50, size: 1.8, opacity: 0.56, glow: 0.04, driftX: 0.8,  driftY: -0.6, color: .white),
        .init(id: 110, x: 0.26, y: 0.42, size: 2.0, opacity: 0.66, glow: 0.05, driftX: -1.2, driftY: 0.7,  color: .white),
        .init(id: 111, x: 0.34, y: 0.54, size: 1.7, opacity: 0.58, glow: 0.04, driftX: 1.0,  driftY: 0.5,  color: .purple),
        .init(id: 112, x: 0.48, y: 0.46, size: 1.9, opacity: 0.60, glow: 0.05, driftX: -0.9, driftY: -0.7, color: .white),
        .init(id: 113, x: 0.62, y: 0.52, size: 1.8, opacity: 0.58, glow: 0.04, driftX: 1.2,  driftY: 0.8,  color: .orange),
        .init(id: 114, x: 0.74, y: 0.44, size: 2.0, opacity: 0.64, glow: 0.05, driftX: -1.1, driftY: 0.5,  color: .white),
        .init(id: 115, x: 0.86, y: 0.54, size: 1.7, opacity: 0.56, glow: 0.04, driftX: 0.8,  driftY: -0.8, color: .white),
        .init(id: 116, x: 0.10, y: 0.78, size: 1.8, opacity: 0.58, glow: 0.05, driftX: -1.2, driftY: 0.7,  color: .purple),
        .init(id: 117, x: 0.24, y: 0.72, size: 1.9, opacity: 0.60, glow: 0.05, driftX: 1.0,  driftY: 0.5,  color: .white),
        .init(id: 118, x: 0.40, y: 0.82, size: 1.8, opacity: 0.58, glow: 0.04, driftX: -0.9, driftY: -0.7, color: .orange),
        .init(id: 119, x: 0.58, y: 0.74, size: 2.0, opacity: 0.66, glow: 0.05, driftX: 1.2,  driftY: 0.8,  color: .white),
        .init(id: 120, x: 0.76, y: 0.84, size: 1.7, opacity: 0.56, glow: 0.04, driftX: -1.1, driftY: 0.7,  color: .white)
    ]

    static let nearField: [StarSeed] = [
        .init(id: 201, x: 0.08, y: 0.30, size: 2.4, opacity: 0.88, glow: 0.10, driftX: 1.3,  driftY: 1.0,  color: .white),
        .init(id: 202, x: 0.18, y: 0.14, size: 2.2, opacity: 0.82, glow: 0.09, driftX: -1.2, driftY: 0.9,  color: .orange),
        .init(id: 203, x: 0.30, y: 0.26, size: 2.6, opacity: 0.90, glow: 0.11, driftX: 1.1,  driftY: -1.0, color: .white),
        .init(id: 204, x: 0.52, y: 0.18, size: 2.3, opacity: 0.84, glow: 0.09, driftX: -1.3, driftY: 0.8,  color: .white),
        .init(id: 205, x: 0.70, y: 0.24, size: 2.5, opacity: 0.88, glow: 0.10, driftX: 1.2,  driftY: 1.0,  color: .purple),
        .init(id: 206, x: 0.86, y: 0.18, size: 2.2, opacity: 0.80, glow: 0.08, driftX: -1.0, driftY: -0.8, color: .white),
        .init(id: 207, x: 0.14, y: 0.58, size: 2.4, opacity: 0.86, glow: 0.10, driftX: 1.3,  driftY: 0.9,  color: .white),
        .init(id: 208, x: 0.38, y: 0.48, size: 2.6, opacity: 0.90, glow: 0.11, driftX: -1.2, driftY: 1.0,  color: .orange),
        .init(id: 209, x: 0.60, y: 0.60, size: 2.3, opacity: 0.84, glow: 0.09, driftX: 1.1,  driftY: -0.9, color: .white),
        .init(id: 210, x: 0.82, y: 0.52, size: 2.5, opacity: 0.88, glow: 0.10, driftX: -1.3, driftY: 0.8,  color: .white),
        .init(id: 211, x: 0.24, y: 0.84, size: 2.2, opacity: 0.82, glow: 0.08, driftX: 1.2,  driftY: 0.9,  color: .purple),
        .init(id: 212, x: 0.50, y: 0.76, size: 2.6, opacity: 0.90, glow: 0.11, driftX: -1.1, driftY: 0.9,  color: .white),
        .init(id: 213, x: 0.74, y: 0.88, size: 2.3, opacity: 0.84, glow: 0.09, driftX: 1.3,  driftY: -0.8, color: .orange)
    ]
}

// MARK: - Optional Grid

private struct GridOverlay: View {
    let spacing: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            Path { path in
                var x: CGFloat = 0
                while x <= width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                    x += spacing
                }

                var y: CGFloat = 0
                while y <= height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                    y += spacing
                }
            }
            .stroke(Color.orange, lineWidth: 1)
        }
    }
}
