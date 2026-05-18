import SwiftUI

enum ParticleBurstStyle {
    case confetti
    case smoke
}

struct ParticleBurstView: View {
    let style: ParticleBurstStyle
    let tint: Color
    let triggerToken: Int

    @State private var particles: [Particle] = []
    @State private var startTime: Date = .distantPast

    private struct Particle: Identifiable {
        let id = UUID()
        let angle: Double
        let speed: Double
        let drift: Double
        let size: CGFloat
        let lifespan: Double
        let hueShift: Double
        let rotationRate: Double
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            Canvas { canvasContext, size in
                guard !particles.isEmpty else { return }
                let elapsed = context.date.timeIntervalSince(startTime)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                for particle in particles {
                    let lifeProgress = min(max(elapsed / particle.lifespan, 0), 1)
                    guard lifeProgress < 1 else { continue }

                    let dx: Double
                    let dy: Double
                    let opacity: Double

                    switch style {
                    case .confetti:
                        let gravity = 320.0 * elapsed * elapsed
                        dx = cos(particle.angle) * particle.speed * elapsed + particle.drift * sin(elapsed * 6)
                        dy = sin(particle.angle) * particle.speed * elapsed + gravity
                        opacity = 1 - lifeProgress
                    case .smoke:
                        dx = cos(particle.angle) * particle.speed * elapsed * 0.6
                        dy = sin(particle.angle) * particle.speed * elapsed * 0.6 - 60 * elapsed
                        opacity = (1 - lifeProgress) * 0.7
                    }

                    let position = CGPoint(x: center.x + dx, y: center.y + dy)
                    let particleColor = particleColor(for: particle, opacity: opacity)
                    let particleSize = particle.size * (style == .smoke ? (1 + lifeProgress * 1.3) : 1)

                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: position.x, y: position.y)
                    transform = transform.rotated(by: CGFloat(particle.rotationRate * elapsed))

                    canvasContext.drawLayer { layer in
                        layer.translateBy(x: position.x, y: position.y)
                        layer.rotate(by: .radians(particle.rotationRate * elapsed))

                        let rect = CGRect(x: -particleSize / 2, y: -particleSize / 2, width: particleSize, height: particleSize)
                        switch style {
                        case .confetti:
                            layer.fill(Path(rect), with: .color(particleColor))
                        case .smoke:
                            layer.fill(Path(ellipseIn: rect), with: .color(particleColor))
                        }
                    }
                }
            }
        }
        .onChange(of: triggerToken) { _, _ in
            generateParticles()
        }
        .onAppear {
            generateParticles()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func particleColor(for particle: Particle, opacity: Double) -> Color {
        switch style {
        case .confetti:
            return Color(hue: (particle.hueShift).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.95, opacity: opacity)
        case .smoke:
            return tint.opacity(opacity * 0.5)
        }
    }

    private func generateParticles() {
        let count = style == .confetti ? 90 : 36
        var generated: [Particle] = []

        for _ in 0..<count {
            let angle: Double
            let speed: Double
            let lifespan: Double
            let size: CGFloat

            switch style {
            case .confetti:
                angle = Double.random(in: -.pi ... 0)
                speed = Double.random(in: 220...480)
                lifespan = Double.random(in: 1.0...1.6)
                size = CGFloat.random(in: 5...10)
            case .smoke:
                angle = Double.random(in: -.pi ... 0)
                speed = Double.random(in: 60...140)
                lifespan = Double.random(in: 1.0...1.6)
                size = CGFloat.random(in: 18...32)
            }

            generated.append(
                Particle(
                    angle: angle,
                    speed: speed,
                    drift: Double.random(in: -25...25),
                    size: size,
                    lifespan: lifespan,
                    hueShift: Double.random(in: 0...1),
                    rotationRate: Double.random(in: -6...6)
                )
            )
        }

        particles = generated
        startTime = .now
    }
}
