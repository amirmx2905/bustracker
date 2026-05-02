import SwiftUI

struct ProfileEditorView: View {
    enum Mode {
        case complete(defaultRole: ProfileRole)
        case edit(Profile)
    }

    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let showsSignOut: Bool

    @State private var role: ProfileRole
    @State private var fullName: String
    @State private var pickupAddress: String
    @State private var pickupLabel: String
    @State private var isBusy = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case fullName
        case pickupAddress
        case pickupLabel
    }

    init(mode: Mode, showsSignOut: Bool = false) {
        self.mode = mode
        self.showsSignOut = showsSignOut

        switch mode {
        case .complete(let defaultRole):
            _role = State(initialValue: defaultRole)
            _fullName = State(initialValue: "")
            _pickupAddress = State(initialValue: "")
            _pickupLabel = State(initialValue: "")

        case .edit(let profile):
            _role = State(initialValue: profile.role)
            _fullName = State(initialValue: profile.fullName)
            _pickupAddress = State(initialValue: profile.pickupAddress ?? "")
            _pickupLabel = State(initialValue: profile.pickupLabel ?? "")
        }
    }

    private var isParent: Bool {
        role == .parent
    }

    private var allowsRoleSelection: Bool {
        if case .complete = mode {
            return true
        }
        return false
    }

    private var title: String {
        switch mode {
        case .complete:
            return "Complete profile"
        case .edit:
            return "Profile"
        }
    }

    private var subtitle: String {
        switch mode {
        case .complete:
            return "Your account exists, but it still needs the profile data required for routing and pickup notifications."
        case .edit:
            return "Keep your account details current so routing and pickup notifications stay accurate."
        }
    }

    private var submitTitle: String {
        switch mode {
        case .complete:
            return "Save profile"
        case .edit:
            return "Update profile"
        }
    }

    private var isFormValid: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!isParent || !pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                headerCard

                if allowsRoleSelection {
                    roleSection
                }

                accountSection

                if let errorMessage {
                    InlineMessage(
                        message: errorMessage,
                        color: .red,
                        icon: "exclamationmark.circle.fill"
                    )
                }

                submitButton

                if showsSignOut {
                    Button("Sign out") {
                        Task { try? await auth.signOut() }
                    }
                    .buttonStyle(NeonOutlineButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .background(Color.appBg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.appBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .disabled(isBusy)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Role")

            Picker("Role", selection: $role) {
                ForEach(ProfileRole.allCases) { role in
                    Text(roleLabel(for: role)).tag(role)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Profile details")

            VStack(spacing: 12) {
                labeledField("Full name") {
                    TextField("", text: $fullName)
                        .textContentType(.name)
                        .focused($focus, equals: .fullName)
                        .onSubmit { focus = isParent ? .pickupAddress : nil }
                        .neonInput(focused: focus == .fullName)
                }

                if isParent {
                    labeledField("Pickup address") {
                        TextField("", text: $pickupAddress)
                            .focused($focus, equals: .pickupAddress)
                            .onSubmit { focus = .pickupLabel }
                            .neonInput(focused: focus == .pickupAddress)
                    }

                    labeledField("Pickup label") {
                        TextField("", text: $pickupLabel)
                            .focused($focus, equals: .pickupLabel)
                            .onSubmit { focus = nil }
                            .neonInput(focused: focus == .pickupLabel)
                    }

                    Text("This address is geocoded before it is saved, so be specific enough to locate the pickup point.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                }
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(isBusy ? "Saving…" : submitTitle)
            }
        }
        .buttonStyle(NeonPrimaryButtonStyle())
        .disabled(isBusy || !isFormValid)
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

    private func roleLabel(for role: ProfileRole) -> String {
        switch role {
        case .parent:
            return "Parent"
        case .driver:
            return "Driver"
        }
    }

    private func submit() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            switch mode {
            case .complete:
                try await auth.completeMissingProfile(
                    role: role,
                    fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                    pickupAddress: isParent ? pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                    pickupLabel: isParent ? pickupLabel.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                )

            case .edit:
                try await auth.updateProfile(
                    fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                    pickupAddress: isParent ? pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                    pickupLabel: isParent ? pickupLabel.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                )
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Complete profile") {
    ProfileEditorView(mode: .complete(defaultRole: .parent), showsSignOut: true)
        .environment(AuthViewModel())
        .preferredColorScheme(.dark)
}
