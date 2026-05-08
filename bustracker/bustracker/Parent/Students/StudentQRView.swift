import SwiftUI

struct StudentQRReadyCard: View {
    let created: CreatedStudent

    var body: some View {
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
}

struct StudentQRDisplayCard: View {
    let qrCode: String
    let isActive: Bool

    var body: some View {
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
}
