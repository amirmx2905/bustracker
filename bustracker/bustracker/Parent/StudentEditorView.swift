import SwiftUI

struct StudentEditorView: View {
    enum Mode {
        case create
        case edit(StudentDirectoryEntry)
    }

    private enum CreateStep: Int, CaseIterable, Identifiable {
        case tag
        case details

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .tag:
                return "Tag"
            case .details:
                return "Details"
            }
        }

        var eyebrow: String {
            "Step \(rawValue + 1)"
        }

        var description: String {
            switch self {
            case .tag:
                return "Capture the student tag first."
            case .details:
                return "Add student info and stops."
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onSaved: @MainActor () async -> Void

    @State private var nfcUID: String
    @State private var fullName: String
    @State private var dateOfBirth: Date
    @State private var pickupAddress: String
    @State private var destinations: [EditableDestination]
    @State private var createStep: CreateStep
    @State private var isBusy = false
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var showArchiveConfirmation = false

    init(mode: Mode, onSaved: @escaping @MainActor () async -> Void) {
        self.mode = mode
        self.onSaved = onSaved

        switch mode {
        case .create:
            let suggestedBirthDate = Calendar.current.date(byAdding: .year, value: -8, to: Date()) ?? Date()
            _nfcUID = State(initialValue: "")
            _fullName = State(initialValue: "")
            _dateOfBirth = State(initialValue: suggestedBirthDate)
            _pickupAddress = State(initialValue: "")
            _destinations = State(initialValue: [EditableDestination()])
            _createStep = State(initialValue: .tag)

        case .edit(let entry):
            _nfcUID = State(initialValue: entry.student.nfcUID)
            _fullName = State(initialValue: entry.student.fullName)
            _dateOfBirth = State(initialValue: entry.student.birthDate ?? Date())
            _pickupAddress = State(initialValue: entry.student.pickupAddress)
            _destinations = State(initialValue: entry.destinations.map(EditableDestination.init(record:)))
            _createStep = State(initialValue: .details)
        }
    }

    private var isCreateMode: Bool {
        switch mode {
        case .create:
            return true
        case .edit:
            return false
        }
    }

    private var title: String {
        switch mode {
        case .create:
            return "Register student"
        case .edit:
            return "Manage student"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create:
            switch createStep {
            case .tag:
                return "Step 1 of 2. Scan the student's NTAG before entering any profile details."
            case .details:
                return "Step 2 of 2. Enter the student's profile, pickup, and destinations before saving."
            }
        case .edit:
            return "Update student details, manage destinations, or archive the student when they no longer ride."
        }
    }

    private var submitTitle: String {
        switch mode {
        case .create:
            return "Create student"
        case .edit:
            return "Save changes"
        }
    }

    private var trimmedNFCUID: String {
        nfcUID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTagStepValid: Bool {
        !trimmedNFCUID.isEmpty
    }

    private var isFormValid: Bool {
        isTagStepValid
            && !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !destinations.isEmpty
            && destinations.allSatisfy {
                !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private var isPrimaryActionEnabled: Bool {
        guard !isBusy, !isScanning else { return false }

        switch mode {
        case .create:
            switch createStep {
            case .tag:
                return isTagStepValid
            case .details:
                return isFormValid
            }
        case .edit:
            return isFormValid
        }
    }

    private var primaryActionTitle: String {
        switch mode {
        case .create:
            switch createStep {
            case .tag:
                return "Continue"
            case .details:
                return submitTitle
            }
        case .edit:
            return submitTitle
        }
    }

    private var canArchive: Bool {
        guard case .edit(let entry) = mode else { return false }
        return entry.student.active
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard

                if isCreateMode {
                    wizardProgress
                }

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isScanning {
                    ProgressView()
                        .tint(.neonBlue)
                }
            }
        }
        .alert("Archive student?", isPresented: $showArchiveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Archive", role: .destructive) {
                Task { await archiveStudent() }
            }
        } message: {
            Text("This keeps the student record but marks it inactive so the NFC tag can be reused later.")
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

    private var wizardProgress: some View {
        HStack(spacing: 12) {
            ForEach(CreateStep.allCases) { step in
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(step == createStep ? Color.neonBlue : Color.appSecondary)

                    Text(step.title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(step.description)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(step == createStep ? Color.neonBlue.opacity(0.14) : Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(step == createStep ? Color.neonBlue : Color.appBorder, lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var contentSections: some View {
        switch mode {
        case .create:
            switch createStep {
            case .tag:
                createTagStepSection
            case .details:
                studentDetailsSection
                destinationsSection
            }
        case .edit:
            editTagSection
            studentDetailsSection
            destinationsSection
        }
    }

    private var createTagStepSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Scan student tag")

            VStack(spacing: 18) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.neonBlue)

                VStack(spacing: 8) {
                    Text("Tap the NTAG to this iPhone")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Hold the tag near the top of the phone. Once the UID is captured, continue to the student details step.")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await scanNFC() }
                } label: {
                    HStack(spacing: 10) {
                        if isScanning {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(isScanning ? "Scanning..." : "Scan student tag")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeonPrimaryButtonStyle())
                .disabled(isScanning || !NFCScanner.isAvailable)

                if !NFCScanner.isAvailable {
                    Text("NFC scanning is unavailable here, so enter the tag UID manually to keep moving.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                        .multilineTextAlignment(.center)
                }

                labeledField("Tag UID") {
                    TextField("Student tag UID", text: $nfcUID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .neonInput()
                }

                Text("You do not need to write student data onto the tag. The app only reads and stores the tag UID.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)

                if isTagStepValid {
                    InlineMessage(
                        message: "Tag captured. Continue to fill in the student profile.",
                        color: .green,
                        icon: "checkmark.circle.fill"
                    )
                }
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
    }

    private var editTagSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "NFC tag")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TextField("Student tag UID", text: $nfcUID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .neonInput()

                    Button {
                        Task { await scanNFC() }
                    } label: {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.neonBlue)
                            .frame(width: 44, height: 44)
                            .background(Color.appInput)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isScanning || !NFCScanner.isAvailable)
                }

                Text(NFCScanner.isAvailable ? "Rescan the student's physical NFC tag or paste the UID manually if you already have it." : "NFC scanning is unavailable here, so enter the tag UID manually.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondary)
            }
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

                labeledField("Pickup address") {
                    TextField("Street, city, state", text: $pickupAddress)
                        .neonInput()
                }

                Text("Pickup and destination addresses are geocoded before saving, so use complete real-world addresses.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondary)
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

    @ViewBuilder
    private var actionSection: some View {
        switch mode {
        case .create:
            if createStep == .tag {
                primaryActionButton
            } else {
                HStack(spacing: 12) {
                    Button {
                        errorMessage = nil
                        createStep = .tag
                    } label: {
                        Text("Back")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeonOutlineButtonStyle())
                    .disabled(isBusy || isScanning)

                    primaryActionButton
                }
            }
        case .edit:
            primaryActionButton

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

    private var primaryActionButton: some View {
        Button {
            handlePrimaryAction()
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }

                Text(isBusy ? "Saving..." : primaryActionTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeonPrimaryButtonStyle())
        .disabled(!isPrimaryActionEnabled)
    }

    private func destinationCard(index: Int) -> some View {
        let destination = $destinations[index]

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

            labeledField("Address") {
                TextField("Destination address", text: destination.address)
                    .neonInput()
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

    @ViewBuilder
    private func labeledField<F: View>(_ label: String, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
            field()
        }
    }

    private func handlePrimaryAction() {
        errorMessage = nil

        switch mode {
        case .create:
            switch createStep {
            case .tag:
                guard isTagStepValid else { return }
                createStep = .details
            case .details:
                Task { await submit() }
            }
        case .edit:
            Task { await submit() }
        }
    }

    private func scanNFC() async {
        errorMessage = nil
        isScanning = true
        defer { isScanning = false }

        do {
            nfcUID = try await NFCScanner.scanUID()
        } catch NFCScannerError.userCancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let input = StudentEditorInput(
                nfcUID: nfcUID,
                fullName: fullName,
                dateOfBirth: dateOfBirth,
                pickupAddress: pickupAddress,
                destinations: destinations
            )

            switch mode {
            case .create:
                try await SupabaseStudentDirectoryService.createStudent(from: input)
            case .edit(let entry):
                try await SupabaseStudentDirectoryService.updateStudent(entry, from: input)
            }

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
