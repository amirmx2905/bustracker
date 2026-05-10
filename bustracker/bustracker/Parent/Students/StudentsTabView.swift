import SwiftUI

struct StudentsTabView: View {
    let profile: Profile

    @State private var students: [StudentDirectoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showStudentCreator = false
    @State private var showLinkStudent = false
    @State private var selectedStudent: StudentDirectoryEntry?
    @State private var qrStudent: StudentDirectoryEntry?

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
                            StudentCard(
                                entry: entry,
                                onShowQR: { qrStudent = entry },
                                onManage: { selectedStudent = entry }
                            )
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
            .sheet(item: $qrStudent) { entry in
                NavigationStack {
                    ScrollView {
                        StudentQRDisplayCard(
                            qrCode: entry.student.qrCode,
                            isActive: entry.student.active
                        )
                        .padding(20)
                    }
                    .background(Color.appBg.ignoresSafeArea())
                    .navigationTitle(entry.student.fullName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(Color.appBg, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { qrStudent = nil }
                                .foregroundStyle(Color.neonBlue)
                        }
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
        HStack(alignment: .center) {
            Text("Hi, \(firstName)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            studentCountBadge
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

    private var studentCountBadge: some View {
        Text("\(students.count) student\(students.count == 1 ? "" : "s")")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.neonBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.neonBlue.opacity(0.15), in: Capsule())
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
    let onShowQR: () -> Void
    let onManage: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            headerRow
            pickupRow
            destinationsRow
            divider
            actionsRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.neonBlue.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Circle().strokeBorder(Color.neonBlue.opacity(0.4), lineWidth: 1)
                    }
                Image(systemName: "person.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.neonBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
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
    }

    private var pickupRow: some View {
        infoRow(
            icon: "figure.walk",
            primary: "Pickup",
            secondary: entry.student.pickupAddress
        )
    }

    private var destinationsRow: some View {
        let count = entry.destinations.count
        if count == 0 {
            return AnyView(infoRow(
                icon: "flag.slash",
                primary: "No destinations",
                secondary: "Add one in Manage to enable this student."
            ))
        }
        let title = "\(count) destination\(count == 1 ? "" : "s")"
        let names = entry.destinations.map(\.label).joined(separator: ", ")
        return AnyView(infoRow(
            icon: "flag.checkered",
            primary: title,
            secondary: names
        ))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.appBorder.opacity(0.6))
            .frame(height: 1)
    }

    private var actionsRow: some View {
        HStack(spacing: 0) {
            Button(action: onShowQR) {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.subheadline.weight(.semibold))
                    Text("Show QR")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.neonBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.appBorder)
                .frame(width: 1, height: 24)

            Button(action: onManage) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                    Text("Manage")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.appSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
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

    private func infoRow(icon: String, primary: String, secondary: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Color.neonBlue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(primary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            Spacer()
        }
    }
}
