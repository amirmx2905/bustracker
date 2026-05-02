import Foundation
import Observation
import Supabase

@Observable
final class AuthViewModel {
    enum AppState {
        case loading
        case unauthenticated
        case needsProfile
        case unavailable(String)
        case authenticated(Profile)
    }

    var appState: AppState = .loading
    var isBiometricLocked: Bool = false

    var currentProfile: Profile? {
        guard case .authenticated(let p) = appState else { return nil }
        return p
    }

    init() {
        Task { await bootstrap() }
    }

    // MARK: - Lifecycle

    /// Called once on app launch. Restores session and engages the biometric
    /// lock if the device supports it. Fresh sign-ins skip the lock because
    /// the user just authenticated with their password.
    func bootstrap() async {
        await refresh()
        if case .authenticated = appState, BiometricService.canUseBiometrics() {
            isBiometricLocked = true
        }
    }

    /// Re-engage the biometric lock when the app returns from background.
    func lockIfAuthenticated() {
        guard case .authenticated = appState, BiometricService.canUseBiometrics() else { return }
        isBiometricLocked = true
    }

    /// Called by `BiometricLockView` after a successful biometric challenge.
    func unlock() {
        isBiometricLocked = false
    }

    // MARK: - State Refresh

    func refresh() async {
        guard (try? await supabase.auth.session) != nil else {
            appState = .unauthenticated
            return
        }
        do {
            try await ensureProfileLoaded()
        } catch {
            // `ensureProfileLoaded()` already set the appropriate state.
        }
    }

    // MARK: - Auth Actions

    func signIn(
        email: String,
        password: String,
        rememberForBiometric: Bool = false
    ) async throws {
        try await supabase.auth.signIn(email: email, password: password)
        try await ensureProfileLoaded()

        if rememberForBiometric,
           BiometricService.canUseBiometrics(),
           case .authenticated = appState {
            try? CredentialStore.save(email: email, password: password)
        }
    }

    /// Sign in using credentials stored in the Keychain.
    /// The Keychain prompts the user for biometrics. If the stored credentials
    /// no longer work (e.g., password changed), they are deleted automatically.
    func signInWithStoredCredentials() async throws {
        let creds = try await CredentialStore.load(
            reason: "Sign in to BusTracker."
        )
        do {
            try await supabase.auth.signIn(email: creds.email, password: creds.password)
        } catch {
            try? CredentialStore.delete()
            throw error
        }
        try await ensureProfileLoaded()
    }

    func signUpParent(
        email: String,
        password: String,
        fullName: String,
        pickupAddress: String,
        pickupLabel: String
    ) async throws {
        let draft = try await makeProfileDraft(
            role: .parent,
            fullName: fullName,
            pickupAddress: pickupAddress,
            pickupLabel: pickupLabel
        )
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: draft.signupMetadata
        )

        guard response.session != nil else {
            throw AuthError.emailConfirmationRequired
        }

        try await ensureProfileLoaded(repairingMissingProfileWith: draft)
    }

    func signUpDriver(email: String, password: String, fullName: String) async throws {
        let draft = try await makeProfileDraft(
            role: .driver,
            fullName: fullName,
            pickupAddress: nil,
            pickupLabel: nil
        )
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: draft.signupMetadata
        )

        guard response.session != nil else {
            throw AuthError.emailConfirmationRequired
        }

        try await ensureProfileLoaded(repairingMissingProfileWith: draft)
    }

    func completeMissingProfile(
        role: ProfileRole,
        fullName: String,
        pickupAddress: String?,
        pickupLabel: String?
    ) async throws {
        let draft = try await makeProfileDraft(
            role: role,
            fullName: fullName,
            pickupAddress: pickupAddress,
            pickupLabel: pickupLabel
        )
        try await ensureProfileLoaded(repairingMissingProfileWith: draft)
    }

    func updateProfile(
        fullName: String,
        pickupAddress: String?,
        pickupLabel: String?
    ) async throws {
        guard case .authenticated(let profile) = appState else {
            throw AuthError.profileMissing
        }

        let draft = try await makeProfileDraft(
            role: profile.role,
            fullName: fullName,
            pickupAddress: pickupAddress,
            pickupLabel: pickupLabel
        )
        try await SupabaseProfileService.updateProfile(from: draft)
        try await ensureProfileLoaded()
    }

    func resendSignupConfirmation(for email: String) async throws {
        try await supabase.auth.resend(email: email, type: .signup)
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
        isBiometricLocked = false
        appState = .unauthenticated
        // Saved credentials are intentionally preserved so the user can sign
        // back in with Face ID. They are biometric-protected in the Keychain,
        // and `save()` overwrites them when a different account signs in.
    }

    // MARK: - Helpers

    private func makeProfileDraft(
        role: ProfileRole,
        fullName: String,
        pickupAddress: String?,
        pickupLabel: String?
    ) async throws -> ProfileDraft {
        let normalizedFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPickupAddress = pickupAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPickupLabel = pickupLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch role {
        case .parent:
            let (lat, lng, formatted) = try await Geocoder.geocode(normalizedPickupAddress ?? "")
            return ProfileDraft(
                role: .parent,
                fullName: normalizedFullName,
                pickupLabel: normalizedPickupLabel,
                pickupAddress: formatted,
                lat: lat,
                lng: lng
            )

        case .driver:
            return ProfileDraft(
                role: .driver,
                fullName: normalizedFullName,
                pickupLabel: nil,
                pickupAddress: nil,
                lat: nil,
                lng: nil
            )
        }
    }

    private func ensureProfileLoaded(
        repairingMissingProfileWith draft: ProfileDraft? = nil
    ) async throws {
        do {
            let profile = try await SupabaseProfileService.fetchMyProfile()
            appState = .authenticated(profile)
            isBiometricLocked = false
        } catch AuthError.profileMissing {
            guard let draft else {
                appState = .needsProfile
                isBiometricLocked = false
                return
            }

            do {
                try await SupabaseProfileService.createProfile(from: draft)
            } catch {
                if let repairedProfile = try? await SupabaseProfileService.fetchMyProfile() {
                    appState = .authenticated(repairedProfile)
                    isBiometricLocked = false
                    return
                }

                appState = .unavailable(error.localizedDescription)
                throw error
            }

            let profile = try await SupabaseProfileService.fetchMyProfile()
            appState = .authenticated(profile)
            isBiometricLocked = false
        } catch {
            appState = .unavailable(error.localizedDescription)
            throw error
        }
    }
}
