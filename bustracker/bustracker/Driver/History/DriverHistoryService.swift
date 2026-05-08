import Foundation
import Supabase

private struct DriverTripIDParams: Encodable {
    let targetTripID: UUID

    enum CodingKeys: String, CodingKey {
        case targetTripID = "target_trip_id"
    }
}

enum SupabaseDriverHistoryService {
    static func fetchTripHistory() async throws -> [TripHistoryEntry] {
        try await supabase
            .rpc("fetch_trip_history_for_driver")
            .execute()
            .value
    }

    static func fetchTripPath(tripID: UUID) async throws -> [TripPositionLatLng] {
        try await supabase
            .from("trip_positions_latlng")
            .select("lat, lng, recorded_at")
            .eq("trip_id", value: tripID.uuidString)
            .order("recorded_at", ascending: true)
            .execute()
            .value
    }

    static func fetchTripEvents(tripID: UUID) async throws -> [TripHistoryEvent] {
        try await supabase
            .rpc("fetch_trip_events_for_driver", params: DriverTripIDParams(targetTripID: tripID))
            .execute()
            .value
    }
}
