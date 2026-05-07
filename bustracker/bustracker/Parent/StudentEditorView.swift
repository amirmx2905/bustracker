import CoreLocation
import SwiftUI

struct StudentEditorView: View {
    enum Mode {
        case create
        case edit(StudentDirectoryEntry)
    }

    private enum CreateStage {
        case form
        case qrReady(CreatedStudent)
    }

    private enum ActivePicker: Identifiable {
        case pickup
        case destination(UUID)

        var id: String {
            switch self {
            case .pickup: return "pickup"
            case .destination(let id): return "destination-\(id.uuidString)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onSaved: @MainActor () async -> Void

    @State private var fullName: String
    @State private var dateOfBirth: Date
    @State private var pickupAddress: String
    @State private var pickupCoordinate: CoordinatePair?
    @State private var destinations: [EditableDestination]
    @State private var createStage: CreateStage
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showArchiveConfirmation = false
    @State private var activePicker: ActivePicker?

    @MainActor init(mode: Mode, onSaved: @escaping @MainActor () async -> Void) {
        self.mode = mode
        self.onSaved = onSaved

        switch mode {
        case .create:
            let suggestedBirthDate = Calendar.current.date(byAdding: .year, value: -8, to: Date()) ?? Date()
            _fullName = State(initialValue: "")
            _dateOfBirth = State(initialValue: suggestedBirthDate)
            _pickupAddress = State(initialValue: "")
            _pickupCoordinate = State(initialValue: nil)
            _destinations = State(initialValue: [EditableDestination()])
            _createStage = State(initialValue: .form)

        case .edit(let entry):
            _fullName = State(initialValue: entry.student.fullName)
            _dateOfBirth = State(initialValue: entry.student.birthDate ?? Date())
            _pickupAddress = State(initialValue: entry.student.pickupAddress)
            _pickupCoordinate = State(initialValue: nil)
            _destinations = State(initialValue: entry.destinations.map(EditableDestination.init(record:)))
            _createStage = State(initialValue: .form)
        }
    }

    private var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    private var title: String {
        switch mode {
        case .create:
            if case .qrReady = createStage {
                return "Student QR ready"
            }
            return "Register student"
        case .edit:
            return "Manage student"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create:
            switch createStage {
            case .form:
                return "Pick the student's pickup and destination on the map. A unique QR code is generated automatically when you save."
            case .qrReady:
                return "Save or print this QR. The driver scans it to check the student in and out, and a co-parent can scan it to link their account."
            }
        case .edit:
            return "Update student details, manage destinations, or archive the student when they no longer ride."
        }
    }

    private var pickupReady: Bool {
        !pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isFormValid: Bool {
        let nameOK = !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let pickupOK: Bool
        switch mode {
        case .create:
            pickupOK = pickupCoordinate != nil
        case .edit:
            pickupOK = pickupReady
        }
        let destinationsOK = !destinations.isEmpty
            && destinations.allSatisfy { destination in
                guard !destination.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                if destination.destinationID == nil {
                    return destination.coordinate != nil
                }
                return !destination.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        return nameOK && pickupOK && destinationsOK
    }

    private var canArchive: Bool {
        guard case .edit(let entry) = mode else { return false }
        return entry.student.active
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                contentSections

                if let errorMessage {
                    InlineMessage(
                        message: errorMessage,
                        color: .red,
                        icon: "exclamationmark.circle.fill"
                    )
                }

                actionSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(Color.appBg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Archive student?", isPresented: $showArchiveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Archive", role: .destructive) {
                Task { await archiveStudent() }
            }
        } message: {
            Text("This keeps the student record but marks it inactive. The QR code will stop working until they ride again.")
        }
        .sheet(item: $activePicker) { picker in
            pickerSheet(for: picker)
        }
        .disabled(isBusy)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
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

    @ViewBuilder
    private var contentSections: some View {
        switch mode {
        case .create:
            switch createStage {
            case .form:
                studentDetailsSection
                pickupSection
                destinationsSection
            case .qrReady(let created):
                qrReadyCard(created: created)
            }
        case .edit(let entry):
            studentDetailsSection
            pickupSection
            destinationsSection
            qrDisplayCard(qrCode: entry.student.qrCode, isActive: entry.student.active)
        }
    }

    private var studentDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Student details")

            VStack(spacing: 14) {
                labeledField("Full name") {
                    TextField("Student name", text: $fullName)
                        .textContentType(.name)
                        .neonInput()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Date of birth")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)

                    DatePicker(
                        "",
                        selection: $dateOfBirth,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.appInput)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.appBorder, lineWidth: 1)
                    }
                }
            }
        }
    }

    private var pickupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Pickup location")

            locationCard(
                address: pickupAddress,
                isPicked: pickupCoordinate != nil,
                emptyTitle: "Set pickup location",
                changeTitle: "Change pickup location"
            ) {
                activePicker = .pickup
            }
        }
    }

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                FormSectionLabel(text: "Destinations")
                Spacer()
                Button {
                    destinations.append(EditableDestination())
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.neonBlue)
                }
            }

            ForEach(destinations.indices, id: \.self) { index in
                destinationCard(index: index)
            }
        }
    }

    private func destinationCard(index: Int) -> some View {
        let destination = $destinations[index]
        let current = destinations[index]

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Destination \(index + 1)")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                if destinations.count > 1 {
                    Button(role: .destructive) {
                        destinations.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.red)
                    }
                }
            }

            labeledField("Label") {
                TextField("School, daycare, practice", text: destination.label)
                    .neonInput()
            }

            locationCard(
                address: current.address,
                isPicked: current.coordinate != nil,
                emptyTitle: "Set destination location",
                changeTitle: "Change destination location"
            ) {
                activePicker = .destination(current.id)
            }
        }
        .padding(18)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private func locationCard(
        address: String,
        isPicked: Bool,
        emptyTitle: String,
        changeTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                if trimmed.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.neonBlue)
                        Text(emptyTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.appSecondary)
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: isPicked ? "mappin.circle.fill" : "mappin.circle")
                            .font(.title3)
                            .foregroundStyle(Color.neonBlue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trimmed)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                            Text(changeTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.neonBlue)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.appSecondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appInput)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pickerSheet(for picker: ActivePicker) -> some View {
        switch picker {
        case .pickup:
            LocationPickerSheet(
                title: "Pickup location",
                initialCenter: defaultPickerCenter()
            ) { picked in
                pickupAddress = picked.address
                pickupCoordinate = CoordinatePair(latitude: picked.latitude, longitude: picked.longitude)
            }
        case .destination(let id):
            LocationPickerSheet(
                title: "Destination location",
                initialCenter: defaultPickerCenter()
            ) { picked in
                guard let index = destinations.firstIndex(where: { $0.id == id }) else { return }
                destinations[index].address = picked.address
                destinations[index].coordinate = CoordinatePair(latitude: picked.latitude, longitude: picked.longitude)
            }
        }
    }

    private func defaultPickerCenter() -> CLLocationCoordinate2D {
        if let pickupCoordinate {
            return CLLocationCoordinate2D(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
        }
        if let firstPicked = destinations.compactMap(\.coordinate).first {
            return CLLocationCoordinate2D(latitude: firstPicked.latitude, longitude: firstPicked.longitude)
        }
        return CLLocationCoordinate2D(latitude: 20.6597, longitude: -103.3496)
    }

    private func qrReadyCard(created: CreatedStudent) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.neonBlue)

            Text("Student created")
                .font(.headline)
                .foregroundStyle(.white)

            QRCodeImage(payload: created.qrCode)
                .frame(width: 220, height: 220)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 6) {
                Text("Code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appSecondary)
                Text(created.qrCode)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            ShareLink(
                item: created.qrCode,
                subject: Text("BusTracker student QR"),
                message: Text("Scan this QR in BusTracker to link this student to your account.")
            ) {
                Label("Share code", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonOutlineButtonStyle())

            Text("Save a screenshot for the driver, and share the code with any co-parent who needs to link this student.")
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private func qrDisplayCard(qrCode: String, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Student QR")

            VStack(spacing: 16) {
                QRCodeImage(payload: qrCode)
                    .frame(width: 200, height: 200)
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .opacity(isActive ? 1 : 0.4)

                VStack(spacing: 4) {
                    Text("Code")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                    Text(qrCode)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }

                ShareLink(
                    item: qrCode,
                    subject: Text("BusTracker student QR"),
                    message: Text("Scan this QR in BusTracker to link this student to your account.")
                ) {
                    Label("Share code", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeonOutlineButtonStyle())

                if !isActive {
                    Text("This student is archived. The QR will not match any scan until they are re-activated.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.appBorder, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        switch mode {
        case .create:
            switch createStage {
            case .form:
                primaryButton(title: isBusy ? "Saving..." : "Create student", enabled: isFormValid && !isBusy) {
                    Task { await submitCreate() }
                }
            case .qrReady:
                primaryButton(title: "Done", enabled: true) {
                    dismiss()
                }
            }
        case .edit:
            primaryButton(title: isBusy ? "Saving..." : "Save changes", enabled: isFormValid && !isBusy) {
                Task { await submitUpdate() }
            }

            if canArchive {
                Button(role: .destructive) {
                    showArchiveConfirmation = true
                } label: {
                    Text("Archive student")
                }
                .buttonStyle(NeonOutlineButtonStyle())
            }
        }
    }

    private func primaryButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeonPrimaryButtonStyle())
        .disabled(!enabled)
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

    private func makeInput() -> StudentEditorInput {
        StudentEditorInput(
            fullName: fullName,
            dateOfBirth: dateOfBirth,
            pickupAddress: pickupAddress,
            pickupCoordinate: pickupCoordinate,
            destinations: destinations
        )
    }

    private func submitCreate() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let created = try await SupabaseStudentDirectoryService.createStudent(from: makeInput())
            await onSaved()
            createStage = .qrReady(created)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitUpdate() async {
        guard case .edit(let entry) = mode else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            try await SupabaseStudentDirectoryService.updateStudent(entry, from: makeInput())
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archiveStudent() async {
        guard case .edit(let entry) = mode else { return }

        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            try await SupabaseStudentDirectoryService.archiveStudent(entry.student.id)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Create student") {
    NavigationStack {
        StudentEditorView(mode: .create, onSaved: { })
    }
    .preferredColorScheme(.dark)
}
