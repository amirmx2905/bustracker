import SwiftUI

struct ParentSettingsTabView: View {
    let profile: Profile

    @Environment(AuthViewModel.self) private var auth
    @State private var showProfileEditor = false
    @State private var showSignOutConfirm = false

    private var initials: String {
        let formatter = PersonNameComponentsFormatter()
        guard let components = formatter.personNameComponents(from: profile.fullName) else {
            return String(profile.fullName.prefix(1)).uppercased()
        }
        let abbreviated = PersonNameComponentsFormatter()
        abbreviated.style = .abbreviated
        return abbreviated.string(from: components)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    profileCard
                    accountSection
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.appBg.ignoresSafeArea())
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showProfileEditor) {
                NavigationStack {
                    ProfileEditorView(mode: .edit(profile))
                }
            }
            .alert("Sign out?", isPresented: $showSignOutConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Sign out", role: .destructive) {
                    Task { try? await auth.signOut() }
                }
            } message: {
                Text("You'll need to sign back in to see your students and live trips.")
            }
        }
    }

    private var profileCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.neonBlue.opacity(0.18))
                    .frame(width: 88, height: 88)
                Circle()
                    .strokeBorder(Color.neonBlue.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 88, height: 88)
                Text(initials)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.neonBlue)
            }

            VStack(spacing: 6) {
                Text(profile.fullName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("PARENT")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.neonBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.neonBlue.opacity(0.15), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ACCOUNT")
            settingsRow(
                icon: "person.crop.circle",
                title: "Edit profile",
                subtitle: "Update your name"
            ) {
                showProfileEditor = true
            }
        }
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            showSignOutConfirm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign out")
            }
            .font(.headline)
            .foregroundStyle(Color.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.red.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(Color.appSecondary)
            .padding(.horizontal, 4)
    }

    private func settingsRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.neonBlue)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appSecondary)
            }
            .padding(16)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
