import Foundation
import Supabase

struct StudentRecord: Decodable, Identifiable {
    let id: UUID
    let fullName: String
    let dateOfBirth: String
    let pickupAddress: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case pickupAddress = "pickup_address"
        case active
    }
}

struct DestinationRecord: Decodable, Identifiable {
    let id: UUID
    let studentID: UUID
    let label: String
    let address: String

    enum CodingKeys: String, CodingKey {
        case id
        case studentID = "student_id"
        case label
        case address
    }
}

struct StudentDirectoryEntry: Identifiable {
    let student: StudentRecord
    let destinations: [DestinationRecord]

    var id: UUID { student.id }
    var primaryDestination: DestinationRecord? { destinations.first }
}

enum SupabaseStudentDirectoryService {
    static func fetchLinkedStudents() async throws -> [StudentDirectoryEntry] {
        let students: [StudentRecord] = try await supabase
            .from("students")
            .select("id, full_name, date_of_birth, pickup_address, active")
            .execute()
            .value

        return try await withThrowingTaskGroup(of: StudentDirectoryEntry.self) { group in
            for student in students {
                group.addTask {
                    let destinations = try await fetchDestinations(for: student.id)
                    return StudentDirectoryEntry(student: student, destinations: destinations)
                }
            }

            var entries: [StudentDirectoryEntry] = []
            for try await entry in group {
                entries.append(entry)
            }

            return entries.sorted {
                $0.student.fullName.localizedCaseInsensitiveCompare($1.student.fullName) == .orderedAscending
            }
        }
    }

    private static func fetchDestinations(for studentID: UUID) async throws -> [DestinationRecord] {
        let destinations: [DestinationRecord] = try await supabase
            .from("destinations")
            .select("id, student_id, label, address")
            .eq("student_id", value: studentID.uuidString)
            .execute()
            .value

        return destinations.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }
}
