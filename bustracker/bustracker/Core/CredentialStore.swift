import Foundation
import LocalAuthentication
import Security

// MARK: - Errors

enum CredentialStoreError: LocalizedError {
    case notFound
    case userCancel
    case biometricsUnavailable
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No saved credentials on this device."
        case .userCancel:
            return "Authentication cancelled."
        case .biometricsUnavailable:
            return "Biometrics is not available on this device."
        case .keychain(let status):
            return "Keychain error (\(status))."
        }
    }
}

// MARK: - Model

struct StoredCredentials: Sendable {
    let email: String
    let password: String
}

// MARK: - Store

enum CredentialStore {
    private static let service = "com.amirmx.bustracker.credentials"
    private static let account = "default"
    private static let separator: Character = "\u{1F}"  // ASCII unit separator

    // MARK: Existence

    /// Returns whether a credential item exists in the Keychain *without*
    /// triggering a biometric prompt. Use this to decide whether to show
    /// the "Sign in with Face ID" button.
    static func hasStoredCredentials() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String:                    kSecClassGenericPassword,
            kSecAttrService as String:              service,
            kSecAttrAccount as String:              account,
            kSecMatchLimit as String:               kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecInteractionNotAllowed (-25308) means the item exists but is
        // ACL-protected — exactly what we want for biometric items.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // MARK: Save

    static func save(email: String, password: String) throws {
        guard BiometricService.canUseBiometrics() else {
            throw CredentialStoreError.biometricsUnavailable
        }

        try? delete()

        let payload = "\(email)\(separator)\(password)".data(using: .utf8) ?? Data()

        var aclError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,
            &aclError
        ) else {
            throw CredentialStoreError.keychain(errSecParam)
        }

        let attributes: [String: Any] = [
            kSecClass as String:             kSecClassGenericPassword,
            kSecAttrService as String:       service,
            kSecAttrAccount as String:       account,
            kSecValueData as String:         payload,
            kSecAttrAccessControl as String: access,
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
    }

    // MARK: Load

    /// Reads the stored credentials, prompting the user for biometrics.
    /// The Keychain itself drives the prompt — we don't call `LAContext`.
    static func load(reason: String) async throws -> StoredCredentials {
        let context = LAContext()
        context.localizedReason = reason

        let query: [String: Any] = [
            kSecClass as String:                    kSecClassGenericPassword,
            kSecAttrService as String:              service,
            kSecAttrAccount as String:              account,
            kSecReturnData as String:               true,
            kSecMatchLimit as String:               kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)

                switch status {
                case errSecSuccess:
                    guard let data = item as? Data,
                          let raw = String(data: data, encoding: .utf8) else {
                        continuation.resume(throwing: CredentialStoreError.keychain(status))
                        return
                    }
                    let parts = raw.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count == 2 else {
                        continuation.resume(throwing: CredentialStoreError.keychain(status))
                        return
                    }
                    continuation.resume(returning: StoredCredentials(
                        email: String(parts[0]),
                        password: String(parts[1])
                    ))
                case errSecItemNotFound:
                    continuation.resume(throwing: CredentialStoreError.notFound)
                case errSecUserCanceled, errSecAuthFailed:
                    continuation.resume(throwing: CredentialStoreError.userCancel)
                default:
                    continuation.resume(throwing: CredentialStoreError.keychain(status))
                }
            }
        }
    }

    // MARK: Delete

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }
}
