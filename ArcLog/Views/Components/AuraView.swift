import SwiftUI

struct AuraView: View {
    var color: Color
    var size: CGFloat = 150
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.28))
                .frame(width: size, height: size)
                .blur(radius: 28)
                .scaleEffect(animate ? 1.05 : 0.9)

            Circle()
                .stroke(color.opacity(0.36), lineWidth: 1)
                .frame(width: size * 0.74, height: size * 0.74)
                .blur(radius: 1.5)
                .scaleEffect(animate ? 1.12 : 0.88)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.85), color.opacity(0.08)],
                        center: .center,
                        startRadius: 8,
                        endRadius: size * 0.34
                    )
                )
                .frame(width: size * 0.58, height: size * 0.58)
        }
        .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: animate)
        .onAppear {
            animate = true
        }
        .accessibilityHidden(true)
    }
}
