import AVFoundation
import SwiftUI

enum QRScannerError: LocalizedError {
    case notAvailable
    case permissionDenied
    case configurationFailed
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "QR scanning is not available on this device."
        case .permissionDenied:
            return "Camera access is required to scan QR codes. Enable it in Settings."
        case .configurationFailed:
            return "The camera could not be configured for QR scanning."
        case .userCancelled:
            return "QR scan cancelled."
        }
    }
}

enum QRScanner {
    static var isAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAuthorization() async -> Bool {
        switch authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (QRScannerError) -> Void
    /// When non-nil, the scanner re-arms itself after this many seconds following each scan,
    /// enabling continuous scanning. nil = single-shot (the original behavior).
    var rearmAfter: Double? = nil

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = onScan
        controller.onError = onError
        controller.rearmAfter = rearmAfter
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        uiViewController.rearmAfter = rearmAfter
    }
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onError: ((QRScannerError) -> Void)?
    var rearmAfter: Double?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.bustracker.qrscanner.session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasReportedScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasReportedScan = false
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            onError?(.configurationFailed)
            return
        }

        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            onError?(.configurationFailed)
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasReportedScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let payload = object.stringValue,
              !payload.isEmpty
        else { return }

        hasReportedScan = true
        onScan?(payload)

        // Continuous mode: re-arm after the requested cooldown so the next student
        // can scan without any tap. The 5s server-side anti-bounce still gates
        // the same QR being re-emitted as a duplicate event.
        if let rearmAfter, rearmAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + rearmAfter) { [weak self] in
                self?.hasReportedScan = false
            }
        }
    }
}
