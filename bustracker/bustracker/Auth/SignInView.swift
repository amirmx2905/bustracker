import SwiftUI

struct SignInView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                fieldsSection
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
        .navigationTitle("Iniciar sesión")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.appBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .disabled(isBusy)
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Tus credenciales")

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Correo electrónico")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                    TextField("", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .neonInput(focused: focus == .email)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Contraseña")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                    SecureField("", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .onSubmit { Task { await signIn() } }
                        .neonInput(focused: focus == .password)
                }
            }
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Task { await signIn() }
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(isBusy ? "Iniciando sesión…" : "Iniciar sesión")
            }
        }
        .buttonStyle(NeonPrimaryButtonStyle())
        .disabled(isBusy || email.isEmpty || password.isEmpty)
    }

    // MARK: - Action

    private func signIn() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch {
            errorMessage = error.localizedDescription
            focus = .email
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
