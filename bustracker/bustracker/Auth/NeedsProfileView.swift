import SwiftUI

struct NeedsProfileView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.07))
                        .frame(width: 160, height: 160)
                        .blur(radius: 20)

                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                        .shadow(color: .orange.opacity(0.6), radius: 8)
                        .shadow(color: .orange.opacity(0.3), radius: 20)
                }
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Profile incomplete")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text("Your account exists but has no profile.\nSign out and try registering again.")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondary)
                        .multilineTextAlignment(.center)
                }

                Button("Sign out") {
                    Task { try? await auth.signOut() }
                }
                .buttonStyle(NeonOutlineButtonStyle())
                .padding(.horizontal, 24)
            }
            .padding(24)
        }
    }
}
