import SwiftUI

struct StudentsTabView: View {
    let profile: Profile

    @State private var students: [StudentDirectoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
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
                VStack(spacing: 18) {
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

                        ForEach(students) { entry in
                            StudentCard(entry: entry) {
                                selectedStudent = entry
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.appBg.ignoresSafeArea())
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await loadStudents() }
            .navigationTitle("Students")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showStudentCreator = true
                        } label: {
                            Label("Register new student", systemImage: "person.badge.plus")
                        }
                        Button {
                            showLinkStudent = true
                        } label: {
                            Label("Link by QR", systemImage: "qrcode.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.neonBlue)
                    }
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Hi, \(firstName)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                statPill(value: "\(students.count)", label: "Students")
                statPill(value: "\(destinationCount)", label: "Stops")
                statPill(value: isLoading ? "Syncing" : "Ready", label: "Status")
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

    private func statPill(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.appSecondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appInput)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.neonBlue)
            Text("Loading linked students...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text("This checks the students and destinations your account is allowed to read.")
                .font(.footnote)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.neonBlue)

            VStack(spacing: 4) {
                Text("No students yet")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Register a new student or link an existing one by QR. Tap the + in the top corner.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
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
        Button(action: onManage) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.student.fullName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Born \(entry.student.birthDateDisplay)")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondary)
                    }
                    Spacer()
                    statusBadge
                }

                infoRow(icon: "figure.walk", label: "Pickup", value: entry.student.pickupAddress)

                if entry.destinations.isEmpty {
                    infoRow(icon: "flag.slash", label: "Destination", value: "No destination has been assigned yet.")
                } else {
                    ForEach(entry.destinations) { destination in
                        infoRow(icon: "flag.checkered", label: destination.label, value: destination.address)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "qrcode")
                        .font(.caption2)
                    Text("QR ready · tap to view")
                }
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        Text(entry.student.active ? "ACTIVE" : "INACTIVE")
            .font(.caption2.weight(.bold))
            .foregroundStyle(entry.student.active ? Color.neonBlue : Color.appSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                (entry.student.active ? Color.neonBlue.opacity(0.15) : Color.appInput),
                in: Capsule()
            )
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.neonBlue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
    }
}
