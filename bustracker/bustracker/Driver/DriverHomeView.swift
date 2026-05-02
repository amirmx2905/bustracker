import SwiftUI

struct DriverHomeView: View {
    let profile: Profile

    @Environment(AuthViewModel.self) private var auth
    @State private var showProfileEditor = false

    private var firstName: String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: profile.fullName) {
            return PersonNameComponentsFormatter.localizedString(from: components, style: .short)
        }
        return profile.fullName
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.neonBlue.opacity(0.07))
                            .frame(width: 160, height: 160)
                            .blur(radius: 24)

                        Circle()
                            .fill(Color.neonBlue.opacity(0.1))
                            .frame(width: 104, height: 104)

                        Image(systemName: "steeringwheel")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.neonBlue)
                            .neonGlow()
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Hi, \(firstName)")
                            .font(.title2.bold())
                            .foregroundStyle(.white)

                        Text("Here you'll start trips\nand scan student NFCs.")
                            .font(.subheadline)
                            .foregroundStyle(Color.appSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("BusTracker — Driver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfileEditor = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(Color.neonBlue)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") {
                        Task { try? await auth.signOut() }
                    }
                    .foregroundStyle(Color.neonBlue)
                }
            }
            .sheet(isPresented: $showProfileEditor) {
                NavigationStack {
                    ProfileEditorView(mode: .edit(profile))
                }
            }
        }
    }
}
