import SwiftUI

struct ContentView: View {
    @State private var auth = AuthViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        rootView
            .environment(auth)
            .preferredColorScheme(.dark)
            .tint(.neonBlue)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    auth.lockIfAuthenticated()
                }
            }
    }

    @ViewBuilder
    private var rootView: some View {
        if auth.isBiometricLocked {
            BiometricLockView()
        } else {
            mainFlow
        }
    }

    @ViewBuilder
    private var mainFlow: some View {
        switch auth.appState {
        case .loading:
            ZStack {
                Color.appBg.ignoresSafeArea()
                ProgressView()
                    .tint(.neonBlue)
            }

        case .unauthenticated:
            LandingView()

        case .needsProfile:
            NeedsProfileView()

        case .unavailable(let message):
            unavailableView(message: message)

        case .authenticated(let profile):
            switch profile.role {
            case .parent:
                ParentRootView(profile: profile)
            case .driver:
                DriverHomeView(profile: profile)
            }
        }
    }

    private func unavailableView(message: String) -> some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.orange)

                VStack(spacing: 8) {
                    Text("Account data unavailable")
                        .font(.title3.bold())
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button("Retry") {
                        Task { await auth.refresh() }
                    }
                    .buttonStyle(NeonPrimaryButtonStyle())

                    Button("Sign out") {
                        Task { try? await auth.signOut() }
                    }
                    .buttonStyle(NeonOutlineButtonStyle())
                }
            }
            .padding(24)
        }
    }
}
