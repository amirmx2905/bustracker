import SwiftUI

struct LinkStudentView: View {
    @Environment(\.dismiss) private var dismiss

    let onLinked: @MainActor () async -> Void

    @State private var qrCode = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showScanner = false
    @State private var scannerError: QRScannerError?

    private var isFormValid: Bool {
        !qrCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        Text(isBusy ? "Linking..." : "Link student")
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
        .sheet(isPresented: $showScanner) {
            scannerSheet
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link an existing student")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Scan the student's QR code from the registrar parent's phone, or paste the code manually.")
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
            FormSectionLabel(text: "Student QR code")

            Button {
                Task { await openScanner() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title3.weight(.semibold))
                    Text("Scan QR code")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonPrimaryButtonStyle())
            .disabled(!QRScanner.isAvailable)

            HStack(spacing: 8) {
                Rectangle().fill(Color.appBorder).frame(height: 1)
                Text("or paste manually")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondary)
                Rectangle().fill(Color.appBorder).frame(height: 1)
            }

            TextField("Student QR code", text: $qrCode)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .neonInput()

            Text(QRScanner.isAvailable
                 ? "The registrar parent can show the QR from their student card, or share the code via Messages."
                 : "Camera scanning is unavailable here. Paste the QR code text manually.")
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                QRScannerView(
                    onScan: { code in
                        qrCode = code
                        showScanner = false
                    },
                    onError: { error in
                        scannerError = error
                        showScanner = false
                    }
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    Text("Center the QR code in view")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle("Scan QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showScanner = false }
                        .foregroundStyle(Color.neonBlue)
                }
            }
        }
        .alert(
            "Scanner unavailable",
            isPresented: Binding(
                get: { scannerError != nil },
                set: { if !$0 { scannerError = nil } }
            ),
            presenting: scannerError
        ) { _ in
            Button("OK", role: .cancel) { scannerError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private func openScanner() async {
        errorMessage = nil
        let granted = await QRScanner.requestAuthorization()
        guard granted else {
            errorMessage = QRScannerError.permissionDenied.localizedDescription
            return
        }
        showScanner = true
    }

    private func submit() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            try await SupabaseStudentDirectoryService.linkStudent(byQRCode: qrCode)
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
