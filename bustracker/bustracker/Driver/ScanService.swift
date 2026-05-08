import CoreLocation
import Foundation
import Supabase

enum ScanOutcome: Equatable {
    case checkIn(studentName: String)
    case checkOut(studentName: String)
    case unknown
    case duplicate

    var iconName: String {
        switch self {
        case .checkIn: return "arrow.down.circle.fill"
        case .checkOut: return "arrow.up.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        case .duplicate: return "clock.badge.exclamationmark.fill"
        }
    }

    var headline: String {
        switch self {
        case .checkIn(let name): return "Checked in: \(name)"
        case .checkOut(let name): return "Checked out: \(name)"
        case .unknown: return "Unknown QR — recorded"
        case .duplicate: return "Duplicate scan ignored"
        }
    }

    var tone: ScanFeedbackTone {
        switch self {
        case .checkIn: return .success
        case .checkOut: return .info
        case .unknown: return .warning
        case .duplicate: return .neutral
        }
    }
}

enum ScanFeedbackTone {
    case success, info, warning, neutral
}

struct TripEventLogEntry: Decodable, Identifiable {
    let id: UUID
    let tripID: UUID
    let type: String
    let studentID: UUID?
    let studentName: String?
    let rawQrPayload: String?
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case type
        case studentID = "student_id"
        case studentName = "student_name"
        case rawQrPayload = "raw_qr_payload"
        case occurredAt = "occurred_at"
    }
}

private struct ScanRPCParams: Encodable {
    let target_trip_id: UUID
    let qr_payload: String
    let scan_lat: Double?
    let scan_lng: Double?
}

private struct ScanRPCRow: Decodable {
    let outcome: String
    let event_id: UUID?
    let student_id: UUID?
    let student_name: String?
}

enum SupabaseScanService {
    static func recordScan(
        tripID: UUID,
        qrPayload: String,
        coordinate: CLLocationCoordinate2D?
    ) async throws -> ScanOutcome {
        let params = ScanRPCParams(
            target_trip_id: tripID,
            qr_payload: qrPayload,
            scan_lat: coordinate?.latitude,
            scan_lng: coordinate?.longitude
        )
        let rows: [ScanRPCRow] = try await supabase
            .rpc("record_scan", params: params)
            .execute()
            .value

        guard let row = rows.first else {
            return .unknown
        }

        switch row.outcome {
        case "check_in":
            return .checkIn(studentName: row.student_name ?? "Unknown student")
        case "check_out":
            return .checkOut(studentName: row.student_name ?? "Unknown student")
        case "unknown_scan":
            return .unknown
        case "duplicate":
            return .duplicate
        default:
            return .unknown
        }
    }

    static func fetchEventLog(tripID: UUID, limit: Int = 50) async throws -> [TripEventLogEntry] {
        try await supabase
            .from("trip_event_log")
            .select("id, trip_id, type, student_id, student_name, raw_qr_payload, occurred_at")
            .eq("trip_id", value: tripID)
            .in("type", values: ["check_in", "check_out"])
            .order("occurred_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }
}
