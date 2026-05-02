import SwiftUI

struct ContentView: View {
    @State private var auth = AuthViewModel()

    var body: some View {
        rootView
            .environment(auth)
            .preferredColorScheme(.dark)
            .tint(.neonBlue)
    }

    @ViewBuilder
    private var rootView: some View {
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
