import SwiftUI

struct StartupView: View {
    var onFinished: (() -> Void)? = nil
    @State private var boltOffset: CGFloat = -60
    @State private var boltOpacity: Double = 0
    @State private var glowScale: CGFloat = 0.8
    @State private var glowOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 20
    @State private var subtitleOpacity: Double = 0
    @State private var starsOpacity: Double = 0
    @State private var flashOpacity: Double = 0

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.14),
                    Color(red: 0.02, green: 0.02, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Star field
            StarsView()
                .opacity(starsOpacity)

            // Flash on bolt arrival
            Circle()
                .fill(.white)
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .opacity(flashOpacity)

            // Glow behind bolt
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 0.2).opacity(0.4),
                            Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.1),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)

            VStack(spacing: 24) {
                // Lightning bolt
                BoltShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.95, blue: 0.7),
                                Color(red: 1.0, green: 0.8, blue: 0.2),
                                Color(red: 0.95, green: 0.65, blue: 0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: 100)
                    .shadow(color: Color(red: 1.0, green: 0.85, blue: 0.2).opacity(0.6), radius: 12, y: 4)
                    .offset(y: boltOffset)
                    .opacity(boltOpacity)

                VStack(spacing: 6) {
                    Text("Recuerdo")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 0.9, green: 0.85, blue: 0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(titleOpacity)
                        .offset(y: titleOffset)

                    Text("flashcards")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.4))
                        .opacity(subtitleOpacity)
                }
                .compositingGroup()
            }
        }
        .onAppear {
            animate()
        }
    }

    private func animate() {
        // Stars fade in first
        withAnimation(.easeIn(duration: 0.8)) {
            starsOpacity = 1
        }

        // Bolt drops in
        withAnimation(.spring(response: 0.25, dampingFraction: 0.55).delay(0.6)) {
            boltOffset = 0
            boltOpacity = 1
        }

        // Flash on landing
        withAnimation(.easeOut(duration: 0.15).delay(0.95)) {
            flashOpacity = 0.6
        }
        withAnimation(.easeOut(duration: 0.4).delay(1.1)) {
            flashOpacity = 0
        }

        // Glow pulses in
        withAnimation(.easeOut(duration: 0.8).delay(1.0)) {
            glowScale = 1.2
            glowOpacity = 1
        }
        withAnimation(.easeInOut(duration: 1.8).delay(1.8)) {
            glowScale = 1.0
            glowOpacity = 0.6
        }

        // Title slides up
        withAnimation(.easeOut(duration: 0.6).delay(1.4)) {
            titleOpacity = 1
            titleOffset = 0
        }

        // Subtitle fades in
        withAnimation(.easeIn(duration: 0.5).delay(1.9)) {
            subtitleOpacity = 1
        }

        // Signal ready to dismiss after animations complete + hold
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            onFinished?()
        }
    }
}

// MARK: - Star Field

private struct StarsView: View {
    // Store normalized 0–1 positions so we can map to actual screen size
    private let stars: [(nx: CGFloat, ny: CGFloat, size: CGFloat, brightness: Double)] = {
        var result: [(CGFloat, CGFloat, CGFloat, Double)] = []
        let rng = SeededRandom(seed: 42)
        for _ in 0..<150 {
            result.append((
                nx: rng.next(),
                ny: rng.next(),
                size: rng.next() * 2.5 + 0.5,
                brightness: rng.next() * 0.6 + 0.2
            ))
        }
        return result
    }()

    var body: some View {
        Canvas { context, size in
            for star in stars {
                let point = CGPoint(x: star.nx * size.width, y: star.ny * size.height)
                let rect = CGRect(
                    x: point.x - star.size / 2,
                    y: point.y - star.size / 2,
                    width: star.size,
                    height: star.size
                )
                context.fill(
                    Circle().path(in: rect),
                    with: .color(.white.opacity(star.brightness))
                )
            }
        }
    }
}

// Deterministic random for consistent star placement
private class SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 32) / CGFloat(UInt32.max)
    }
}
