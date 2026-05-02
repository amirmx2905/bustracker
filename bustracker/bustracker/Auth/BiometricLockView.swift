import SwiftUI

struct BiometricLockView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.scenePhase) private var scenePhase

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var hasAutoPrompted = false
    @State private var autoRetryCount = 0

    private let biometric: BiometricType = BiometricService.availableBiometric()

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                lockIcon
                heading
                if let errorMessage {
                    InlineMessage(
                        message: errorMessage,
                        color: .orange,
                        icon: "exclamationmark.triangle.fill"
                    )
                    .padding(.horizontal, 24)
                }
                Spacer()
                actions
            }
            .padding(.bottom, 32)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                hasAutoPrompted = false
                autoRetryCount = 0
                return
            }
            await maybeAutoAuthenticate()
        }
    }

    // MARK: - Sections

    private var lockIcon: some View {
        ZStack {
            Circle()
                .fill(Color.neonBlue.opacity(0.07))
                .frame(width: 180, height: 180)
                .blur(radius: 24)

            Circle()
                .fill(Color.neonBlue.opacity(0.1))
                .frame(width: 120, height: 120)

            Image(systemName: biometric.iconName)
                .font(.system(size: 56))
                .foregroundStyle(Color.neonBlue)
                .neonGlow()
        }
        .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(spacing: 10) {
            Text("BusTracker is locked")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(headingSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    private var headingSubtitle: String {
        biometric == .none
            ? "Sign out and sign in again to continue."
            : "Use \(biometric.label) to continue."
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if biometric != .none {
                Button {
                    Task { await authenticate() }
                } label: {
                    HStack(spacing: 10) {
                        if isAuthenticating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: biometric.iconName)
                        }
                        Text(isAuthenticating ? "Verifying…" : "Unlock with \(biometric.label)")
                    }
                }
                .buttonStyle(NeonPrimaryButtonStyle())
                .disabled(isAuthenticating)
            }

            Button("Sign out") {
                Task { try? await auth.signOut() }
            }
            .buttonStyle(NeonOutlineButtonStyle())
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Action

    private func maybeAutoAuthenticate() async {
        guard scenePhase == .active, !hasAutoPrompted, !isAuthenticating, biometric != .none else {
            return
        }

        try? await Task.sleep(nanoseconds: 150_000_000)

        guard scenePhase == .active, !hasAutoPrompted, !isAuthenticating, biometric != .none else {
            return
        }

        hasAutoPrompted = true
        await authenticate(triggeredAutomatically: true)
    }

    private func authenticate(triggeredAutomatically: Bool = false) async {
        guard !isAuthenticating, biometric != .none else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        errorMessage = nil

        do {
            try await BiometricService.authenticate(
                reason: "Unlock BusTracker to access your account."
            )
            autoRetryCount = 0
            auth.unlock()
        } catch BiometricError.userCancel {
            return
        } catch BiometricError.transient {
            if triggeredAutomatically, autoRetryCount < 1 {
                autoRetryCount += 1
                hasAutoPrompted = false
                await maybeAutoAuthenticate()
                return
            }
            errorMessage = BiometricError.transient.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    BiometricLockView()
        .environment(AuthViewModel())
        .preferredColorScheme(.dark)
}
