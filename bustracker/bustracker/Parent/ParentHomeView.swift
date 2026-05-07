import SwiftUI

struct ParentHomeView: View {
    let profile: Profile

    @Environment(AuthViewModel.self) private var auth
    @State private var students: [StudentDirectoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showProfileEditor = false
    @State private var showStudentCreator = false
    @State private var showLinkStudent = false
    @State private var selectedStudent: StudentDirectoryEntry?

    private var firstName: String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: profile.fullName) {
            return PersonNameComponentsFormatter.localizedString(from: components, style: .short)
        }
        return profile.fullName
    }

    private var destinationCount: Int {
        students.reduce(0) { $0 + $1.destinations.count }
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
                            StudentCard(entry: entry) {
                                selectedStudent = entry
                            }
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
                    Menu {
                        Button {
                            showStudentCreator = true
                        } label: {
                            Label("Register student", systemImage: "person.badge.plus")
                        }

                        Button {
                            showLinkStudent = true
                        } label: {
                            Label("Link by QR", systemImage: "qrcode.viewfinder")
                        }

                        Divider()

                        Button(role: .destructive) {
                            Task { try? await auth.signOut() }
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.neonBlue)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfileEditor = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(Color.neonBlue)
                    }
                }
            }
            .sheet(isPresented: $showProfileEditor) {
                NavigationStack {
                    ProfileEditorView(mode: .edit(profile))
                }
            }
            .sheet(isPresented: $showStudentCreator) {
                NavigationStack {
                    StudentEditorView(mode: .create) {
                        await loadStudents()
                    }
                }
            }
            .sheet(isPresented: $showLinkStudent) {
                NavigationStack {
                    LinkStudentView {
                        await loadStudents()
                    }
                }
            }
            .sheet(item: $selectedStudent) { entry in
                NavigationStack {
                    StudentEditorView(mode: .edit(entry)) {
                        await loadStudents()
                    }
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
                statPill(title: "Stops", value: "\(destinationCount)")
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

            Text("Register a student from this account or link an existing student by scanning their QR code.")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)

            HStack(spacing: 12) {
                Button {
                    showStudentCreator = true
                } label: {
                    Text("Register student")
                }
                .buttonStyle(NeonPrimaryButtonStyle())

                Button {
                    showLinkStudent = true
                } label: {
                    Text("Link by QR")
                }
                .buttonStyle(NeonOutlineButtonStyle())
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

    private var summaryText: String {
        if isLoading {
            return "Refreshing the students linked to your account."
        }
        if students.isEmpty {
            return "This is now the operational parent workspace for creating, linking, and managing students."
        }
        return "Manage student profiles, share QR codes with co-parents, and keep destination data current from here."
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
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.student.fullName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Born \(entry.student.birthDateDisplay)")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondary)

                    HStack(spacing: 6) {
                        Image(systemName: "qrcode")
                            .font(.caption2)
                        Text("QR ready · tap Manage to view")
                    }
                    .font(.caption)
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

            if entry.destinations.isEmpty {
                infoRow(icon: "flag.slash", label: "Destination", value: "No destination has been assigned yet.")
            } else {
                ForEach(entry.destinations) { destination in
                    infoRow(icon: "flag.checkered", label: destination.label, value: destination.address)
                }
            }

            Button("Manage student") {
                onManage()
            }
            .buttonStyle(NeonOutlineButtonStyle())
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
