import SwiftUI

struct SignInView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var rememberForBiometric = true
    @State private var isBusy = false
    @State private var isBiometricBusy = false
    @State private var errorMessage: String?
    @State private var hasStoredCredentials = CredentialStore.hasStoredCredentials()
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private let biometric = BiometricService.availableBiometric()
    private var canUseBiometric: Bool { biometric != .none }
    private var showBiometricButton: Bool { hasStoredCredentials && canUseBiometric }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero

                if showBiometricButton {
                    biometricSignInButton
                    orDivider
                }

                fieldsSection

                if canUseBiometric && !showBiometricButton {
                    rememberToggle
                }

                if let errorMessage {
                    InlineMessage(
                        message: errorMessage,
                        color: .red,
                        icon: "exclamationmark.circle.fill"
                    )
                }

                submitButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
        .background(Color.appBg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .disabled(isBusy || isBiometricBusy)
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

            Text("Welcome back")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Sign in to keep tracking\nthe journey.")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Biometric Sign-In

    private var biometricSignInButton: some View {
        Button {
            Task { await signInWithBiometrics() }
        } label: {
            HStack(spacing: 10) {
                if isBiometricBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: biometric.iconName)
                }
                Text(isBiometricBusy ? "Verifying…" : "Sign in with \(biometric.label)")
            }
        }
        .buttonStyle(NeonPrimaryButtonStyle())
        .disabled(isBiometricBusy || isBusy)
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.appBorder).frame(height: 1)
            Text("or")
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
            Rectangle().fill(Color.appBorder).frame(height: 1)
        }
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Your credentials")

            VStack(spacing: 12) {
                labeledField("Email") {
                    TextField("", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .neonInput(focused: focus == .email)
                }

                labeledField("Password") {
                    SecureField("", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .onSubmit { Task { await signIn() } }
                        .neonInput(focused: focus == .password)
                }
            }
        }
    }

    @ViewBuilder
    private func labeledField<F: View>(_ label: String, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
            field()
        }
    }

    // MARK: - Remember Toggle

    private var rememberToggle: some View {
        Toggle(isOn: $rememberForBiometric) {
            HStack(spacing: 8) {
                Image(systemName: biometric.iconName)
                    .foregroundStyle(Color.neonBlue)
                Text("Save to sign in with \(biometric.label)")
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondary)
            }
        }
        .tint(.neonBlue)
    }

    // MARK: - Submit

    @ViewBuilder
    private var submitButton: some View {
        if showBiometricButton {
            Button { Task { await signIn() } } label: {
                HStack(spacing: 10) {
                    if isBusy { ProgressView().tint(.neonBlue) }
                    Text(isBusy ? "Signing in…" : "Use email and password")
                }
            }
            .buttonStyle(NeonOutlineButtonStyle())
            .disabled(isBusy || isBiometricBusy || email.isEmpty || password.isEmpty)
        } else {
            Button { Task { await signIn() } } label: {
                HStack(spacing: 10) {
                    if isBusy { ProgressView().tint(.white) }
                    Text(isBusy ? "Signing in…" : "Sign in")
                }
            }
            .buttonStyle(NeonPrimaryButtonStyle())
            .disabled(isBusy || isBiometricBusy || email.isEmpty || password.isEmpty)
        }
    }

    // MARK: - Actions

    private func signIn() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                rememberForBiometric: rememberForBiometric
            )
        } catch {
            errorMessage = error.localizedDescription
            focus = .email
        }
    }

    private func signInWithBiometrics() async {
        guard !isBiometricBusy else { return }
        isBiometricBusy = true
        defer { isBiometricBusy = false }
        errorMessage = nil
        do {
            try await auth.signInWithStoredCredentials()
        } catch CredentialStoreError.userCancel {
            return
        } catch CredentialStoreError.notFound {
            hasStoredCredentials = false
            errorMessage = "No saved credentials. Please sign in manually."
        } catch {
            // If Supabase rejected the stored creds, AuthViewModel already deleted them.
            hasStoredCredentials = CredentialStore.hasStoredCredentials()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        SignInView()
            .environment(AuthViewModel())
    }
    .preferredColorScheme(.dark)
}
