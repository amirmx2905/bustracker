import Foundation
import MapKit
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

struct ProfileDraft {
    let role: ProfileRole
    let fullName: String
    let pickupLabel: String?
    let pickupAddress: String?
    let lat: Double?
    let lng: Double?

    private var normalizedPickupLabel: String? {
        guard role == .parent else { return nil }
        if let pickupLabel, !pickupLabel.isEmpty {
            return pickupLabel
        }
        return "Home"
    }

    private var pickupPointWKT: String? {
        guard let lat, let lng else { return nil }
        return "SRID=4326;POINT(\(lng) \(lat))"
    }

    var signupMetadata: [String: AnyJSON] {
        var metadata: [String: AnyJSON] = [
            "role": .string(role.rawValue),
            "full_name": .string(fullName)
        ]

        if let pickupLabel = normalizedPickupLabel {
            metadata["pickup_label"] = .string(pickupLabel)
        }
        if let pickupAddress {
            metadata["pickup_address"] = .string(pickupAddress)
        }
        if let pickupPointWKT {
            metadata["pickup_point"] = .string(pickupPointWKT)
        }

        return metadata
    }

    fileprivate var createPayload: ProfileInsertPayload {
        ProfileInsertPayload(
            id: UUID(),
            role: role.rawValue,
            full_name: fullName,
            pickup_label: normalizedPickupLabel,
            pickup_address: pickupAddress,
            pickup_point: pickupPointWKT
        )
    }

    fileprivate var updatePayload: ProfileUpdatePayload {
        ProfileUpdatePayload(
            role: role.rawValue,
            full_name: fullName,
            pickup_label: normalizedPickupLabel,
            pickup_address: pickupAddress,
            pickup_point: pickupPointWKT
        )
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case addressNotFound
    case geocodingFailed(Error)
    case emailConfirmationRequired
    case profileMissing

    var errorDescription: String? {
        switch self {
        case .addressNotFound:
            "Address not found. Try being more specific."
        case .geocodingFailed(let e):
            "Error verifying address: \(e.localizedDescription)"
        case .emailConfirmationRequired:
            "Check your email and confirm your account, then sign in."
        case .profileMissing:
            "Your account is missing its profile. Complete it to continue."
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

private struct ProfileUpdatePayload: Encodable {
    let role: String
    let full_name: String
    let pickup_label: String?
    let pickup_address: String?
    let pickup_point: String?
}

enum SupabaseProfileService {
    static func fetchMyProfile() async throws -> Profile {
        let session = try await supabase.auth.session
        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select("id, role, full_name, pickup_label, pickup_address")
            .eq("id", value: session.user.id)
            .limit(1)
            .execute()
            .value

        guard let profile = profiles.first else {
            throw AuthError.profileMissing
        }

        return profile
    }

    static func createProfile(from draft: ProfileDraft) async throws {
        let session = try await supabase.auth.session
        var payload = draft.createPayload
        payload = ProfileInsertPayload(
            id: session.user.id,
            role: payload.role,
            full_name: payload.full_name,
            pickup_label: payload.pickup_label,
            pickup_address: payload.pickup_address,
            pickup_point: payload.pickup_point
        )

        _ = try await supabase
            .from("profiles")
            .insert(payload)
            .execute()
    }

    static func updateProfile(from draft: ProfileDraft) async throws {
        let session = try await supabase.auth.session

        _ = try await supabase
            .from("profiles")
            .update(draft.updatePayload)
            .eq("id", value: session.user.id)
            .execute()
    }
}

// MARK: - Geocoder

enum Geocoder {
    static func geocode(_ address: String) async throws -> (lat: Double, lng: Double, formatted: String) {
        guard let request = MKGeocodingRequest(addressString: address) else {
            throw AuthError.addressNotFound
        }

        do {
            let mapItems = try await request.mapItems

            guard let mapItem = mapItems.first else {
                throw AuthError.addressNotFound
            }

            let coordinate = mapItem.location.coordinate
            let formatted = mapItem.addressRepresentations?
                .fullAddress(includingRegion: true, singleLine: true)
                ?? mapItem.name
                ?? address

            return (
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                formatted: formatted
            )
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.geocodingFailed(error)
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
