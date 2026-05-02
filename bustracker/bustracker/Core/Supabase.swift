import Foundation
import CoreLocation
import Supabase

// MARK: - Domain Models

enum ProfileRole: String, CaseIterable, Identifiable, Codable {
    case parent
    case driver
    var id: String { rawValue }
}

struct Profile: Decodable {
    let id: UUID
    let role: ProfileRole
    let fullName: String
    let pickupLabel: String?
    let pickupAddress: String?

    enum CodingKeys: String, CodingKey {
        case id, role
        case fullName = "full_name"
        case pickupLabel = "pickup_label"
        case pickupAddress = "pickup_address"
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case addressNotFound
    case geocodingFailed(Error)
    case emailConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .addressNotFound:
            "Address not found. Try being more specific."
        case .geocodingFailed(let e):
            "Error verifying address: \(e.localizedDescription)"
        case .emailConfirmationRequired:
            "Check your email and confirm your account, then sign in."
        }
    }
}

// MARK: - Profile Service

private struct ProfileInsertPayload: Encodable {
    let id: UUID
    let role: String
    let full_name: String
    let pickup_label: String?
    let pickup_address: String?
    let pickup_point: String? // WKT "SRID=4326;POINT(lng lat)"
}

enum SupabaseProfileService {
    static func fetchMyProfile() async throws -> Profile {
        try await supabase
            .from("profiles")
            .select("id, role, full_name, pickup_label, pickup_address")
            .single()
            .execute()
            .value
    }

    static func createProfile(
        role: ProfileRole,
        fullName: String,
        pickupAddress: String?,
        pickupLabel: String?,
        lat: Double?,
        lng: Double?
    ) async throws {
        let session = try await supabase.auth.session
        let wkt: String? = {
            guard let lat, let lng else { return nil }
            return "SRID=4326;POINT(\(lng) \(lat))"
        }()
        let payload = ProfileInsertPayload(
            id: session.user.id,
            role: role.rawValue,
            full_name: fullName,
            pickup_label: pickupLabel,
            pickup_address: pickupAddress,
            pickup_point: wkt
        )
        _ = try await supabase
            .from("profiles")
            .insert(payload)
            .execute()
    }
}

// MARK: - Geocoder

enum Geocoder {
    static func geocode(_ address: String) async throws -> (lat: Double, lng: Double, formatted: String) {
        try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().geocodeAddressString(address) { placemarks, error in
                if let error {
                    continuation.resume(throwing: AuthError.geocodingFailed(error))
                    return
                }
                guard let placemark = placemarks?.first, let location = placemark.location else {
                    continuation.resume(throwing: AuthError.addressNotFound)
                    return
                }
                let parts = [placemark.thoroughfare, placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }
                let formatted = parts.isEmpty ? address : parts.joined(separator: ", ")
                continuation.resume(returning: (
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude,
                    formatted: formatted
                ))
            }
        }
    }
}

// MARK: - Supabase Client

private struct SupabaseConfig {
    let url: URL
    let key: String

    static func load() -> SupabaseConfig {
        let env = ProcessInfo.processInfo.environment
        let file = DotEnv.loadFromBundle()
        let urlString = env["SUPABASE_URL"] ?? file["SUPABASE_URL"]
        let key = env["SUPABASE_KEY"] ?? file["SUPABASE_KEY"]

        guard
            let urlString,
            let url = URL(string: urlString),
            let key,
            !key.isEmpty
        else {
            fatalError("Missing Supabase config. Set SUPABASE_URL and SUPABASE_KEY in scheme env vars or .env file.")
        }
        return SupabaseConfig(url: url, key: key)
    }
}

private enum DotEnv {
    static func loadFromBundle() -> [String: String] {
        guard
            let url = Bundle.main.url(forResource: ".env", withExtension: nil)
                ?? Bundle.main.url(forResource: "env", withExtension: nil),
            let raw = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }

        var values: [String: String] = [:]
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespaces)
            let v = parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !k.isEmpty { values[k] = v }
        }
        return values
    }
}

private let _config = SupabaseConfig.load()

let supabase = SupabaseClient(
    supabaseURL: _config.url,
    supabaseKey: _config.key
)
