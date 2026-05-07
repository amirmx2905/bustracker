import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum QRGenerator {
    static func makeImage(from payload: String, scale: CGFloat = 10) -> UIImage? {
        guard let data = payload.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct QRCodeImage: View {
    let payload: String
    var scale: CGFloat = 10

    var body: some View {
        if let image = QRGenerator.makeImage(from: payload, scale: scale) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR code for student")
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("QR code unavailable")
        }
    }
}
