import Foundation
import Supabase

struct ActiveTripForParent: Decodable, Identifiable {
    let tripID: UUID
    let studentID: UUID
    let studentName: String
    let checkInAt: Date
    let tripStartedAt: Date

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case studentID = "student_id"
        case studentName = "student_name"
        case checkInAt = "check_in_at"
        case tripStartedAt = "trip_started_at"
    }

    /// Synthetic id so SwiftUI can keep two cards distinct when the same trip
    /// has two of this parent's students onboard.
    var id: String { "\(tripID.uuidString)-\(studentID.uuidString)" }
}

struct TripPositionLatLng: Decodable, Equatable {
    let lat: Double
    let lng: Double
    let recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case lat
        case lng
        case recordedAt = "recorded_at"
    }
}

enum SupabaseParentLiveTripService {
    static func fetchActiveTrips() async throws -> [ActiveTripForParent] {
        try await supabase
            .rpc("fetch_active_trips_for_parent")
            .execute()
            .value
    }

    static func fetchLatestPosition(tripID: UUID) async throws -> TripPositionLatLng? {
        let rows: [TripPositionLatLng] = try await supabase
            .from("trip_positions_latlng")
            .select("lat, lng, recorded_at")
            .eq("trip_id", value: tripID.uuidString)
            .order("recorded_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Returns the bus's full path for this trip (oldest → newest), used to draw a
    /// polyline on the map. Capped to keep MapKit snappy on long trips.
    static func fetchPositionPath(tripID: UUID, limit: Int = 500) async throws -> [TripPositionLatLng] {
        try await supabase
            .from("trip_positions_latlng")
            .select("lat, lng, recorded_at")
            .eq("trip_id", value: tripID.uuidString)
            .order("recorded_at", ascending: true)
            .limit(limit)
            .execute()
            .value
    }
}
