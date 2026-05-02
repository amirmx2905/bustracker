import Foundation
import LocalAuthentication

// MARK: - Biometric Type

enum BiometricType {
    case none
    case touchID
    case faceID
    case opticID

    var label: String {
        switch self {
        case .none:    return "Biometrics"
        case .touchID: return "Touch ID"
        case .faceID:  return "Face ID"
        case .opticID: return "Optic ID"
        }
    }

    var iconName: String {
        switch self {
        case .none:    return "lock.fill"
        case .touchID: return "touchid"
        case .faceID:  return "faceid"
        case .opticID: return "opticid"
        }
    }
}

// MARK: - Biometric Error

enum BiometricError: LocalizedError, Equatable {
    case notAvailable
    case notEnrolled
    case lockout
    case userCancel
    case transient
    case failed
    case unknown

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Biometrics is not available on this device."
        case .notEnrolled:  return "Set up Face ID or Touch ID in Settings to continue."
        case .lockout:      return "Biometrics locked. Unlock with your passcode."
        case .userCancel:   return "Authentication cancelled."
        case .transient:    return "Face ID is temporarily unavailable. Try again."
        case .failed:       return "Authentication failed. Please try again."
        case .unknown:      return "An unexpected error occurred."
        }
    }
}

// MARK: - Service

enum BiometricService {

    /// Returns the biometric type configured on this device, or `.none`
    /// if biometrics are unavailable or not enrolled.
    static func availableBiometric() -> BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        ) else {
            return .none
        }
        switch context.biometryType {
        case .faceID:  return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default:       return .none
        }
    }

    /// Convenience flag for callers that don't care which biometric type is in use.
    static func canUseBiometrics() -> Bool {
        availableBiometric() != .none
    }

    /// Prompts the user for a biometric challenge. Throws on failure or cancel.
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedFallbackTitle = ""

        var canEvaluateError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &canEvaluateError
        ) else {
            throw mapError(canEvaluateError)
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if !success { throw BiometricError.failed }
        } catch let error as LAError {
            throw mapError(error as NSError)
        } catch {
            throw BiometricError.unknown
        }
    }

    // MARK: - Error Mapping

    private static func mapError(_ nsError: NSError?) -> BiometricError {
        guard let nsError, let code = LAError.Code(rawValue: nsError.code) else {
            return .unknown
        }
        switch code {
        case .biometryNotAvailable:
            return .notAvailable
        case .biometryNotEnrolled:
            return .notEnrolled
        case .biometryLockout:
            return .lockout
        case .userCancel:
            return .userCancel
        case .appCancel, .systemCancel, .invalidContext, .notInteractive:
            return .transient
        case .authenticationFailed, .userFallback, .passcodeNotSet:
            return .failed
        default:
            return .unknown
        }
    }
}
