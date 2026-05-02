import Foundation
import Observation
import Supabase

@Observable
final class AuthViewModel {
    enum AppState {
        case loading
        case unauthenticated
        case needsProfile
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
            let profile = try await SupabaseProfileService.fetchMyProfile()
            appState = .authenticated(profile)
        } catch {
            appState = .needsProfile
        }
    }

    // MARK: - Auth Actions

    func signIn(
        email: String,
        password: String,
        rememberForBiometric: Bool = false
    ) async throws {
        try await supabase.auth.signIn(email: email, password: password)
        await refresh()
        isBiometricLocked = false

        if rememberForBiometric, BiometricService.canUseBiometrics() {
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
        await refresh()
        isBiometricLocked = false
    }

    func signUpParent(
        email: String,
        password: String,
        fullName: String,
        pickupAddress: String,
        pickupLabel: String
    ) async throws {
        let (lat, lng, formatted) = try await Geocoder.geocode(pickupAddress)
        let response = try await supabase.auth.signUp(email: email, password: password)

        guard response.session != nil else {
            throw AuthError.emailConfirmationRequired
        }

        do {
            try await SupabaseProfileService.createProfile(
                role: .parent,
                fullName: fullName,
                pickupAddress: formatted,
                pickupLabel: pickupLabel.isEmpty ? "Home" : pickupLabel,
                lat: lat,
                lng: lng
            )
        } catch {
            try? await supabase.auth.signOut()
            throw error
        }
        await refresh()
        isBiometricLocked = false
    }

    func signUpDriver(email: String, password: String, fullName: String) async throws {
        let response = try await supabase.auth.signUp(email: email, password: password)

        guard response.session != nil else {
            throw AuthError.emailConfirmationRequired
        }

        do {
            try await SupabaseProfileService.createProfile(
                role: .driver,
                fullName: fullName,
                pickupAddress: nil,
                pickupLabel: nil,
                lat: nil,
                lng: nil
            )
        } catch {
            try? await supabase.auth.signOut()
            throw error
        }
        await refresh()
        isBiometricLocked = false
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
        isBiometricLocked = false
        appState = .unauthenticated
        // Saved credentials are intentionally preserved so the user can sign
        // back in with Face ID. They are biometric-protected in the Keychain,
        // and `save()` overwrites them when a different account signs in.
    }
}
