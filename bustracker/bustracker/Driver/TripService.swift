import CoreLocation
import Foundation
import Supabase

struct TripRecord: Decodable, Identifiable {
    let id: UUID
    let driverID: UUID
    let startedAt: Date
    let endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case driverID = "driver_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct GPSGapRecord: Decodable {
    let id: Int
    let tripID: UUID
    let gapStart: Date
    let gapEnd: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case gapStart = "gap_start"
        case gapEnd = "gap_end"
    }
}

struct TripStats {
    var positionsCount: Int
    var gapsCount: Int
    var lastPositionAt: Date?
}

private struct LastPositionRow: Decodable {
    let recorded_at: Date
}

enum TripServiceError: LocalizedError {
    case alreadyActive
    case notFound
    case backendUnavailable
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .alreadyActive:
            return "You already have an active trip. End it before starting another."
        case .notFound:
            return "No active trip found."
        case .backendUnavailable:
            return "The trip RPCs are missing on the backend. Re-run supabase/sql/functions.sql."
        case .decodingFailed:
            return "The server responded with an unexpected shape."
        }
    }
}

private struct TripIDParams: Encodable {
    let targetTripID: UUID

    enum CodingKeys: String, CodingKey {
        case targetTripID = "target_trip_id"
    }
}

private struct TripPositionInsert: Encodable {
    let trip_id: UUID
    let point: String
    let recorded_at: String
}

private struct GPSGapOpenInsert: Encodable {
    let trip_id: UUID
    let gap_start: String
}

private struct GPSGapClosePayload: Encodable {
    let gap_end: String
}

enum SupabaseTripService {
    /// Pulls the running totals for an active trip so the driver UI doesn't reset to 0
    /// after a relaunch. All three queries can run in parallel.
    static func fetchTripStats(tripID: UUID) async throws -> TripStats {
        async let positionsCount = countRows(table: "trip_positions", tripID: tripID)
        async let gapsCount = countRows(table: "gps_gaps", tripID: tripID)
        async let lastAt = fetchLastPositionAt(tripID: tripID)

        let stats = try await TripStats(
            positionsCount: positionsCount,
            gapsCount: gapsCount,
            lastPositionAt: lastAt
        )
        return stats
    }

    private static func countRows(table: String, tripID: UUID) async throws -> Int {
        // Fetch just the ids and use array length. The Content-Range header path
        // (head: true, count: .exact) returned nil for response.count under our
        // supabase-swift version, so this is the boring-but-reliable approach.
        // Both trip_positions and gps_gaps have a bigserial `id`.
        struct CountableRow: Decodable { let id: Int }
        let rows: [CountableRow] = try await supabase
            .from(table)
            .select("id")
            .eq("trip_id", value: tripID.uuidString)
            .execute()
            .value
        return rows.count
    }

    private static func fetchLastPositionAt(tripID: UUID) async throws -> Date? {
        let rows: [LastPositionRow] = try await supabase
            .from("trip_positions")
            .select("recorded_at")
            .eq("trip_id", value: tripID.uuidString)
            .order("recorded_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?.recorded_at
    }

    static func fetchActiveTrip() async throws -> TripRecord? {
        let session = try await supabase.auth.session
        let trips: [TripRecord] = try await supabase
            .from("trips")
            .select("id, driver_id, started_at, ended_at")
            .eq("driver_id", value: session.user.id)
            .is("ended_at", value: nil)
            .limit(1)
            .execute()
            .value
        return trips.first
    }

    static func startTrip() async throws -> UUID {
        do {
            let id: UUID = try await supabase
                .rpc("start_trip")
                .execute()
                .value
            return id
        } catch {
            throw mapBackendError(error)
        }
    }

    static func endTrip(_ tripID: UUID) async throws {
        do {
            try await supabase
                .rpc("end_trip", params: TripIDParams(targetTripID: tripID))
                .execute()
        } catch {
            throw mapBackendError(error)
        }
    }

    static func pushPosition(tripID: UUID, coordinate: CLLocationCoordinate2D, at timestamp: Date) async throws {
        let payload = TripPositionInsert(
            trip_id: tripID,
            point: makeWKT(coordinate: coordinate),
            recorded_at: PGISODate.string(from: timestamp)
        )
        try await supabase
            .from("trip_positions")
            .insert(payload)
            .execute()
    }

    /// Inserts a row into `gps_gaps` with `gap_end = null`. Returns the inserted row's id
    /// so the caller can close it later.
    static func openGap(tripID: UUID, gapStart: Date) async throws -> Int {
        let payload = GPSGapOpenInsert(
            trip_id: tripID,
            gap_start: PGISODate.string(from: gapStart)
        )
        let inserted: [GPSGapRecord] = try await supabase
            .from("gps_gaps")
            .insert(payload, returning: .representation)
            .select("id, trip_id, gap_start, gap_end")
            .execute()
            .value
        guard let row = inserted.first else {
            throw TripServiceError.decodingFailed
        }
        return row.id
    }

    static func closeGap(gapID: Int, gapEnd: Date) async throws {
        let payload = GPSGapClosePayload(gap_end: PGISODate.string(from: gapEnd))
        try await supabase
            .from("gps_gaps")
            .update(payload)
            .eq("id", value: gapID)
            .execute()
    }

    private static func makeWKT(coordinate: CLLocationCoordinate2D) -> String {
        "SRID=4326;POINT(\(coordinate.longitude) \(coordinate.latitude))"
    }

    private static func mapBackendError(_ error: Error) -> Error {
        let message = error.localizedDescription.lowercased()
        if message.contains("you already have an active trip") {
            return TripServiceError.alreadyActive
        }
        if message.contains("no active trip") {
            return TripServiceError.notFound
        }
        if message.contains("function") && message.contains("schema cache") {
            return TripServiceError.backendUnavailable
        }
        return error
    }
}

enum PGISODate {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
