import Foundation

#if canImport(CoreNFC)
import CoreNFC
#endif

enum NFCScannerError: LocalizedError {
    case notAvailable
    case scanInProgress
    case unsupportedTag
    case userCancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "NFC scanning is not available on this device."
        case .scanInProgress:
            return "An NFC scan is already in progress."
        case .unsupportedTag:
            return "This NFC tag type is not supported by the app yet."
        case .userCancelled:
            return "NFC scan cancelled."
        case .failed(let message):
            return message
        }
    }
}

enum NFCScanner {
    static var isAvailable: Bool {
        #if canImport(CoreNFC)
        return NFCTagReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    @MainActor
    static func scanUID(prompt: String = "Hold your phone near the student's NFC tag.") async throws -> String {
        #if canImport(CoreNFC)
        return try await NFCScannerSession.shared.scanUID(prompt: prompt)
        #else
        throw NFCScannerError.notAvailable
        #endif
    }
}

#if canImport(CoreNFC)
@MainActor
private final class NFCScannerSession: NSObject, NFCTagReaderSessionDelegate {
    static let shared = NFCScannerSession()

    private var continuation: CheckedContinuation<String, Error>?
    private var session: NFCTagReaderSession?

    func scanUID(prompt: String) async throws -> String {
        guard NFCTagReaderSession.readingAvailable else {
            throw NFCScannerError.notAvailable
        }

        guard continuation == nil else {
            throw NFCScannerError.scanInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            guard let session = NFCTagReaderSession(
                pollingOption: [.iso14443, .iso15693, .iso18092],
                delegate: self,
                queue: nil
            ) else {
                self.continuation = nil
                continuation.resume(throwing: NFCScannerError.notAvailable)
                return
            }
            session.alertMessage = prompt

            self.session = session
            session.begin()
        }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) { }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error) {
        guard continuation != nil else {
            self.session = nil
            return
        }

        finish(with: .failure(map(error)))
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            finish(with: .failure(NFCScannerError.unsupportedTag))
            return
        }

        guard tags.count == 1 else {
            session.alertMessage = "Hold only one NFC tag near the phone."
            session.restartPolling()
            return
        }

        session.connect(to: tag) { error in
            if let error {
                Task { @MainActor in
                    self.finish(with: .failure(self.map(error)))
                }
                return
            }

            guard let uid = self.makeUID(from: tag) else {
                session.alertMessage = "The detected NFC tag is not supported."
                session.invalidate()
                Task { @MainActor in
                    self.finish(with: .failure(NFCScannerError.unsupportedTag))
                }
                return
            }

            session.alertMessage = "Student tag captured successfully."
            session.invalidate()

            Task { @MainActor in
                self.finish(with: .success(uid))
            }
        }
    }

    private func finish(with result: Result<String, Error>) {
        let continuation = continuation
        self.continuation = nil
        session = nil

        switch result {
        case .success(let uid):
            continuation?.resume(returning: uid)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func makeUID(from tag: NFCTag) -> String? {
        let identifier: Data?

        switch tag {
        case .miFare(let mifareTag):
            identifier = mifareTag.identifier
        case .iso15693(let iso15693Tag):
            identifier = iso15693Tag.identifier
        case .iso7816(let iso7816Tag):
            identifier = iso7816Tag.identifier
        case .feliCa(let feliCaTag):
            identifier = Data(feliCaTag.currentIDm)
        @unknown default:
            identifier = nil
        }

        return identifier?.map { String(format: "%02X", $0) }.joined()
    }

    private func map(_ error: Error) -> Error {
        guard let readerError = error as? NFCReaderError else {
            return NFCScannerError.failed(error.localizedDescription)
        }

        switch readerError.code {
        case .readerSessionInvalidationErrorUserCanceled:
            return NFCScannerError.userCancelled
        case .readerSessionInvalidationErrorSystemIsBusy,
             .readerTransceiveErrorSessionInvalidated,
             .readerErrorUnsupportedFeature:
            return NFCScannerError.failed(readerError.localizedDescription)
        default:
            return NFCScannerError.failed(readerError.localizedDescription)
        }
    }
}
#endif
