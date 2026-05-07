import SwiftUI

struct LandingView: View {
    private enum Destination: Hashable {
        case signIn
        case signUp(role: ProfileRole)
    }

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.appBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    hero
                    Spacer()
                    rolePicker
                    Spacer().frame(height: 28)
                    signInLink
                    Spacer().frame(height: 52)
                }
                .padding(.horizontal, 24)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .signIn:   SignInView()
                case .signUp(let role): SignUpView(role: role)
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.neonBlue.opacity(0.07))
                    .frame(width: 180, height: 180)
                    .blur(radius: 24)

                Circle()
                    .fill(Color.neonBlue.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "bus.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.neonBlue)
                    .neonGlow()
            }
            .accessibilityHidden(true)

            Text("BusTracker")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Track your child's journey\nin real time.")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Role Picker

    private var rolePicker: some View {
        VStack(spacing: 14) {
            Text("What's your role?")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appSecondary)
                .tracking(1.2)
                .frame(maxWidth: .infinity, alignment: .leading)

            roleCard(
                title: "I'm a parent",
                subtitle: "Get trip notifications",
                icon: "person.2.fill",
                isPrimary: true
            ) {
                path.append(Destination.signUp(role: .parent))
            }

            roleCard(
                title: "I'm a driver",
                subtitle: "Run trips and scan QR codes",
                icon: "car.fill",
                isPrimary: false
            ) {
                path.append(Destination.signUp(role: .driver))
            }
        }
    }

    // MARK: - Sign In Link

    private var signInLink: some View {
        Button("Already have an account? Sign in") {
            path.append(Destination.signIn)
        }
        .font(.subheadline)
        .foregroundStyle(Color.appSecondary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.neonBlue.opacity(0.5))
                .offset(y: 2)
        }
    }

    // MARK: - Role Card

    @ViewBuilder
    private func roleCard(
        title: String,
        subtitle: String,
        icon: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.neonBlue.opacity(0.12))
                        .frame(width: 48, height: 48)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.neonBlue.opacity(0.3), lineWidth: 1)
                        }
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(Color.neonBlue)
                        .neonGlow(inner: 4, outer: 10)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.neonBlue.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isPrimary ? Color.neonBlue.opacity(0.35) : Color.appBorder,
                        lineWidth: 1
                    )
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

#Preview {
    LandingView()
        .environment(AuthViewModel())
        .preferredColorScheme(.dark)
}
