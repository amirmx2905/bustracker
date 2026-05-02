import SwiftUI

struct LinkStudentView: View {
    @Environment(\.dismiss) private var dismiss

    let onLinked: @MainActor () async -> Void

    @State private var nfcUID = ""
    @State private var isBusy = false
    @State private var isScanning = false
    @State private var errorMessage: String?

    private var isFormValid: Bool {
        !nfcUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                formSection

                if let errorMessage {
                    InlineMessage(
                        message: errorMessage,
                        color: .red,
                        icon: "exclamationmark.circle.fill"
                    )
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 10) {
                        if isBusy {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isBusy ? "Linking…" : "Link student")
                    }
                }
                .buttonStyle(NeonPrimaryButtonStyle())
                .disabled(isBusy || !isFormValid)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(Color.appBg.ignoresSafeArea())
        .navigationTitle("Link student")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .disabled(isBusy)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link an existing student")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Scan the student's NFC tag to attach this parent account to an already registered student record.")
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

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormSectionLabel(text: "Student NFC tag")

            HStack(spacing: 10) {
                TextField("Student tag UID", text: $nfcUID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .neonInput()

                Button {
                    Task { await scanNFC() }
                } label: {
                    if isScanning {
                        ProgressView()
                            .tint(.neonBlue)
                            .frame(width: 44, height: 44)
                            .background(Color.appInput)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.neonBlue)
                            .frame(width: 44, height: 44)
                            .background(Color.appInput)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .disabled(isScanning || !NFCScanner.isAvailable)
            }

            Text(NFCScanner.isAvailable ? "Use the student's physical tag or paste the UID if you already know it." : "NFC scanning is unavailable here, so enter the tag UID manually.")
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
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
            try await SupabaseStudentDirectoryService.linkStudent(byNFCUID: nfcUID)
            await onLinked()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        LinkStudentView(onLinked: { })
    }
    .preferredColorScheme(.dark)
}
