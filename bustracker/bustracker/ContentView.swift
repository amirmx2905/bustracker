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

        case .authenticated(let profile):
            switch profile.role {
            case .parent:
                ParentHomeView(profile: profile)
            case .driver:
                DriverHomeView(profile: profile)
            }
        }
    }
}
