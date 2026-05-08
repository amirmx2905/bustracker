import SwiftUI

struct SignUpView: View {
    let role: ProfileRole

    @Environment(AuthViewModel.self) private var auth

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showEmailConfirmationAlert = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case fullName, email, password, confirmPassword
    }

    private var isParent: Bool { role == .parent }

    private var isFormValid: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && emailLooksValid
            && password.count >= 6
            && password == confirmPassword
    }

    private var emailLooksValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@"),
              atIndex != trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: atIndex)...]
        return domain.contains(".") && !domain.hasSuffix(".")
    }

    private var heroIcon: String { isParent ? "person.2.fill" : "bus.fill" }
    private var heroTitle: String {
        isParent ? "Create your\nparent account" : "Create your\ndriver account"
    }
    private var heroSubtitle: String {
        isParent
            ? "Join BusTracker to keep eyes\non every ride."
            : "Run trips, scan QRs,\nshare GPS in real time."
    }

    private var benefits: [(icon: String, text: String)] {
        if isParent {
            return [
                ("location.fill", "Real-time bus location"),
                ("qrcode.viewfinder", "Scan-in / scan-out"),
                ("map.fill", "Trip history with full route")
            ]
        } else {
            return [
                ("play.circle.fill", "Start trips with one tap"),
                ("qrcode.viewfinder", "Scan students in and out"),
                ("list.bullet.rectangle", "Full trip log and GPS history")
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                benefitsCard
                accountSection
                PasswordChecklist(password: password, confirmPassword: confirmPassword)

                if let error = errorMessage {
                    InlineMessage(message: error, color: .red, icon: "exclamationmark.circle.fill")
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

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.neonBlue.opacity(0.07))
                    .frame(width: 160, height: 160)
                    .blur(radius: 24)
                Circle()
                    .fill(Color.neonBlue.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: heroIcon)
                    .font(.system(size: 44))
                    .foregroundStyle(Color.neonBlue)
                    .neonGlow()
            }
            .accessibilityHidden(true)

            Text(heroTitle)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Benefits Card

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(benefits, id: \.text) { benefit in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.neonBlue.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: benefit.icon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.neonBlue)
                    }
                    Text(benefit.text)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.appBorder, lineWidth: 1)
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

                labeledField("Password") {
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
                        .onSubmit { focus = nil }
                        .neonInput(focused: focus == .confirmPassword)
                }
            }
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
                Text(isBusy ? "Creating account..." : "Create account")
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

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if isParent {
                try await auth.signUpParent(
                    email: trimmedEmail,
                    password: password,
                    fullName: trimmedFullName
                )
            } else {
                try await auth.signUpDriver(
                    email: trimmedEmail,
                    password: password,
                    fullName: trimmedFullName
                )
            }
        } catch AuthError.emailConfirmationRequired {
            showEmailConfirmationAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Parent") {
    NavigationStack {
        SignUpView(role: .parent)
            .environment(AuthViewModel())
    }
    .preferredColorScheme(.dark)
}

#Preview("Driver") {
    NavigationStack {
        SignUpView(role: .driver)
            .environment(AuthViewModel())
    }
    .preferredColorScheme(.dark)
}
