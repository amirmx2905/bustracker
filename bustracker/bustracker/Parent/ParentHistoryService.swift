import Foundation
import Supabase

struct TripHistoryEntry: Decodable, Identifiable {
    let tripID: UUID
    let startedAt: Date
    let endedAt: Date
    let studentNames: [String]
    let eventCount: Int

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case studentNames = "student_names"
        case eventCount = "event_count"
    }

    var id: UUID { tripID }
}

struct TripHistoryEvent: Decodable, Identifiable {
    let eventID: UUID
    let eventType: String
    let studentID: UUID?
    let studentName: String?
    let occurredAt: Date
    let lat: Double?
    let lng: Double?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case eventType = "event_type"
        case studentID = "student_id"
        case studentName = "student_name"
        case occurredAt = "occurred_at"
        case lat
        case lng
    }

    var id: UUID { eventID }
}

private struct TripIDParams: Encodable {
    let targetTripID: UUID

    enum CodingKeys: String, CodingKey {
        case targetTripID = "target_trip_id"
    }
}

enum SupabaseParentHistoryService {
    static func fetchTripHistory() async throws -> [TripHistoryEntry] {
        try await supabase
            .rpc("fetch_trip_history_for_parent")
            .execute()
            .value
    }

    static func fetchTripPath(tripID: UUID) async throws -> [TripPositionLatLng] {
        try await supabase
            .rpc("fetch_trip_path_for_parent", params: TripIDParams(targetTripID: tripID))
            .execute()
            .value
    }

    static func fetchTripEvents(tripID: UUID) async throws -> [TripHistoryEvent] {
        try await supabase
            .rpc("fetch_trip_events_for_parent", params: TripIDParams(targetTripID: tripID))
            .execute()
            .value
    }

    static func hideTrip(tripID: UUID) async throws {
        try await supabase
            .rpc("hide_trip_from_history", params: TripIDParams(targetTripID: tripID))
            .execute()
    }
}
