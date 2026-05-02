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

    var currentProfile: Profile? {
        guard case .authenticated(let p) = appState else { return nil }
        return p
    }

    init() {
        Task { await refresh() }
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

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
        await refresh()
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
                pickupLabel: pickupLabel.isEmpty ? "Casa" : pickupLabel,
                lat: lat,
                lng: lng
            )
        } catch {
            try? await supabase.auth.signOut()
            throw error
        }
        await refresh()
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
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
        appState = .unauthenticated
    }
}
