import SwiftUI

struct DriverIdleHero<Action: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 22) {
            glowingBus

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            action()
                .padding(.horizontal, 24)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glowingBus: some View {
        ZStack {
            Circle()
                .fill(Color.neonBlue.opacity(0.08))
                .frame(width: 140, height: 140)
                .blur(radius: 20)
            Circle()
                .fill(Color.neonBlue.opacity(0.12))
                .frame(width: 96, height: 96)
            Image(systemName: "bus")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.neonBlue)
                .neonGlow(inner: 6, outer: 14)
        }
    }
}
