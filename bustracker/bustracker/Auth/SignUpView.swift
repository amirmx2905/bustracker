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
                        message: "Las contraseñas no coinciden.",
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
        .navigationTitle(isParent ? "Registro de responsable" : "Registro de conductor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.appBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .disabled(isBusy)
        .alert("Confirma tu correo", isPresented: $showEmailConfirmationAlert) {
            Button("Entendido", role: .cancel) { }
        } message: {
            Text("Te enviamos un correo de confirmación. Una vez que confirmes tu cuenta, inicia sesión.")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Tus datos")

            VStack(spacing: 12) {
                labeledField("Nombre completo") {
                    TextField("", text: $fullName)
                        .textContentType(.name)
                        .focused($focus, equals: .fullName)
                        .onSubmit { focus = .email }
                        .neonInput(focused: focus == .fullName)
                }

                labeledField("Correo electrónico") {
                    TextField("", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .neonInput(focused: focus == .email)
                }

                labeledField("Contraseña (mín. 6 caracteres)") {
                    SecureField("", text: $password)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .password)
                        .onSubmit { focus = .confirmPassword }
                        .neonInput(focused: focus == .password)
                }

                labeledField("Confirmar contraseña") {
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
            FormSectionLabel(text: "Parada de recogida")

            VStack(spacing: 12) {
                labeledField("Dirección") {
                    TextField("", text: $pickupAddress)
                        .focused($focus, equals: .pickupAddress)
                        .onSubmit { focus = .pickupLabel }
                        .neonInput(focused: focus == .pickupAddress)
                }

                labeledField("Etiqueta (ej. Casa, Trabajo)") {
                    TextField("", text: $pickupLabel)
                        .focused($focus, equals: .pickupLabel)
                        .onSubmit { focus = nil }
                        .neonInput(focused: focus == .pickupLabel)
                }
            }

            Text("Recibirás una notificación cuando el bus esté cerca de esta dirección.")
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
                Text(isBusy ? "Creando cuenta…" : "Crear cuenta")
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
