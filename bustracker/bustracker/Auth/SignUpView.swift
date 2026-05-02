import SwiftUI

struct SignUpView: View {
    let role: ProfileRole

    @Environment(AuthViewModel.self) private var auth

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var pickupAddress = ""
    @State private var pickupLabel = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showEmailConfirmationAlert = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case fullName, email, password, confirmPassword, pickupAddress, pickupLabel
    }

    private var isParent: Bool { role == .parent }

    private var isFormValid: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.isEmpty
            && password.count >= 6
            && password == confirmPassword
            && (!isParent || !pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var passwordMismatch: Bool {
        !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                accountSection
                if isParent { pickupSection }
                if passwordMismatch {
                    InlineMessage(
                        message: "Passwords don't match.",
                        color: .orange,
                        icon: "exclamationmark.triangle.fill"
                    )
                }
                if let error = errorMessage {
                    InlineMessage(message: error, color: .red, icon: "exclamationmark.circle.fill")
                }
                submitButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .background(Color.appBg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(isParent ? "Parent sign-up" : "Driver sign-up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.appBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .disabled(isBusy)
        .alert("Confirm your email", isPresented: $showEmailConfirmationAlert) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("We sent you a confirmation email. Once you confirm your account, sign in.")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Your details")

            VStack(spacing: 12) {
                labeledField("Full name") {
                    TextField("", text: $fullName)
                        .textContentType(.name)
                        .focused($focus, equals: .fullName)
                        .onSubmit { focus = .email }
                        .neonInput(focused: focus == .fullName)
                }

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

                labeledField("Password (min. 6 characters)") {
                    SecureField("", text: $password)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .password)
                        .onSubmit { focus = .confirmPassword }
                        .neonInput(focused: focus == .password)
                }

                labeledField("Confirm password") {
                    SecureField("", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .confirmPassword)
                        .onSubmit { focus = isParent ? .pickupAddress : nil }
                        .neonInput(focused: focus == .confirmPassword)
                }
            }
        }
    }

    // MARK: - Pickup Section

    private var pickupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Pickup stop")

            VStack(spacing: 12) {
                labeledField("Address") {
                    TextField("", text: $pickupAddress)
                        .focused($focus, equals: .pickupAddress)
                        .onSubmit { focus = .pickupLabel }
                        .neonInput(focused: focus == .pickupAddress)
                }

                labeledField("Label (e.g. Home, Work)") {
                    TextField("", text: $pickupLabel)
                        .focused($focus, equals: .pickupLabel)
                        .onSubmit { focus = nil }
                        .neonInput(focused: focus == .pickupLabel)
                }
            }

            Text("You'll get a notification when the bus is near this address.")
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(isBusy ? "Creating account…" : "Create account")
            }
        }
        .buttonStyle(NeonPrimaryButtonStyle())
        .disabled(isBusy || !isFormValid)
        .sensoryFeedback(.success, trigger: auth.currentProfile != nil)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func labeledField<F: View>(_ label: String, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
            field()
        }
    }

    // MARK: - Action

    private func submit() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            if isParent {
                try await auth.signUpParent(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                    pickupAddress: pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines),
                    pickupLabel: pickupLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } else {
                try await auth.signUpDriver(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } catch AuthError.emailConfirmationRequired {
            showEmailConfirmationAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Responsable") {
    NavigationStack {
        SignUpView(role: .parent)
            .environment(AuthViewModel())
    }
    .preferredColorScheme(.dark)
}

#Preview("Conductor") {
    NavigationStack {
        SignUpView(role: .driver)
            .environment(AuthViewModel())
    }
    .preferredColorScheme(.dark)
}
