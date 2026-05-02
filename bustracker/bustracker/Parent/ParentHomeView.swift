import SwiftUI

struct ParentHomeView: View {
    let profile: Profile

    @Environment(AuthViewModel.self) private var auth
    @State private var students: [StudentDirectoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard

                    if let errorMessage, students.isEmpty {
                        InlineMessage(
                            message: errorMessage,
                            color: .red,
                            icon: "exclamationmark.circle.fill"
                        )
                    }

                    if isLoading && students.isEmpty {
                        loadingCard
                    } else if students.isEmpty {
                        emptyCard
                    } else {
                        if let errorMessage {
                            InlineMessage(
                                message: errorMessage,
                                color: .orange,
                                icon: "exclamationmark.triangle.fill"
                            )
                        }

                        Text("Linked students")
                            .font(.headline)
                            .foregroundStyle(.white)

                        ForEach(students) { entry in
                            StudentCard(entry: entry)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color.appBg.ignoresSafeArea())
            .scrollBounceBehavior(.basedOnSize)
            .refreshable {
                await loadStudents()
            }
            .navigationTitle("BusTracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await loadStudents() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.neonBlue)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color.neonBlue)
                        }
                    }
                    .disabled(isLoading)
                }

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
            .task {
                guard students.isEmpty, errorMessage == nil else { return }
                await loadStudents()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hi, \(firstName)")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)

            HStack(spacing: 12) {
                statPill(title: "Students", value: "\(students.count)")
                statPill(title: "Status", value: isLoading ? "Syncing" : "Ready")
            }
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

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.neonBlue)

            Text("Loading linked students...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Text("This checks the students and destinations your account is allowed to read.")
                .font(.footnote)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
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

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No linked students yet")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Phase 2 needs demo rows in students, student_parents, and destinations before this screen can populate.")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)

            Button {
                Task { await loadStudents() }
            } label: {
                Text("Check again")
            }
            .buttonStyle(NeonOutlineButtonStyle())
            .disabled(isLoading)
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

    private var summaryText: String {
        if isLoading {
            return "Refreshing the students linked to your account."
        }
        if students.isEmpty {
            return "Your linked students will appear here once the Phase 2 demo data is seeded."
        }
        return "You can now verify that this account only reads its assigned students and destinations."
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.appSecondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.appInput)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @MainActor
    private func loadStudents() async {
        isLoading = true
        defer { isLoading = false }

        do {
            students = try await SupabaseStudentDirectoryService.fetchLinkedStudents()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StudentCard: View {
    let entry: StudentDirectoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.student.fullName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Born \(entry.student.dateOfBirth)")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondary)
                }

                Spacer()

                Text(entry.student.active ? "ACTIVE" : "INACTIVE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.student.active ? Color.neonBlue : Color.appSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.appInput)
                    .clipShape(Capsule())
            }

            infoRow(icon: "figure.walk", label: "Pickup", value: entry.student.pickupAddress)

            if let destination = entry.primaryDestination {
                infoRow(icon: "flag.checkered", label: destination.label, value: destination.address)
            } else {
                infoRow(icon: "flag.slash", label: "Destination", value: "No destination has been assigned yet.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.neonBlue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }

            Spacer()
        }
    }
}
