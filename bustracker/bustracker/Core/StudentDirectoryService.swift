import Foundation
import Supabase

struct StudentRecord: Decodable, Identifiable {
    let id: UUID
    let nfcUID: String
    let fullName: String
    let dateOfBirth: String
    let pickupAddress: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case nfcUID = "nfc_uid"
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case pickupAddress = "pickup_address"
        case active
    }

    var birthDate: Date? {
        StudentDateCodec.parse(dateOfBirth)
    }

    var birthDateDisplay: String {
        guard let birthDate else { return dateOfBirth }
        return birthDate.formatted(date: .abbreviated, time: .omitted)
    }
}

struct DestinationRecord: Decodable, Identifiable, Equatable {
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

struct EditableDestination: Identifiable, Equatable {
    let id: UUID
    let destinationID: UUID?
    var label: String
    var address: String

    init(destinationID: UUID? = nil, label: String = "", address: String = "") {
        self.id = UUID()
        self.destinationID = destinationID
        self.label = label
        self.address = address
    }

    init(record: DestinationRecord) {
        self.id = UUID()
        self.destinationID = record.id
        self.label = record.label
        self.address = record.address
    }
}

struct StudentEditorInput {
    let nfcUID: String
    let fullName: String
    let dateOfBirth: Date
    let pickupAddress: String
    let destinations: [EditableDestination]
}

enum StudentManagementError: LocalizedError {
    case nfcUIDRequired
    case duplicateNFCUID
    case fullNameRequired
    case pickupAddressRequired
    case destinationRequired
    case destinationIncomplete
    case duplicateStudent
    case duplicateDestination
    case databaseUpdateRequired
    case createdStudentMissing

    var errorDescription: String? {
        switch self {
        case .nfcUIDRequired:
            return "Scan an NFC tag before saving the student."
        case .duplicateNFCUID:
            return "This NFC tag is already linked to another active student."
        case .fullNameRequired:
            return "Student name is required."
        case .pickupAddressRequired:
            return "Pickup address is required."
        case .destinationRequired:
            return "Students must have at least one destination."
        case .destinationIncomplete:
            return "Every destination needs both a label and an address."
        case .duplicateStudent:
            return "An active student with the same name and date of birth already exists. Use Link by NFC or manage the existing student instead."
        case .duplicateDestination:
            return "This student already has that destination. Remove the duplicate or change its label/address."
        case .databaseUpdateRequired:
            return "The database is missing the latest Phase 3 duplicate protections. Rerun supabase/sql/phase3_students_and_relationships.sql and try again."
        case .createdStudentMissing:
            return "The student was created, but the app could not refresh its data. Pull to refresh and try again."
        }
    }
}

private enum StudentDateCodec {
    static func parse(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    static func stringify(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct CreateStudentParams: Encodable {
    let studentNFCUID: String
    let studentFullName: String
    let studentDateOfBirth: String
    let studentPickupAddress: String
    let studentPickupLat: Double
    let studentPickupLng: Double
    let destinationLabel: String
    let destinationAddress: String
    let destinationLat: Double
    let destinationLng: Double

    enum CodingKeys: String, CodingKey {
        case studentNFCUID = "student_nfc_uid"
        case studentFullName = "student_full_name"
        case studentDateOfBirth = "student_date_of_birth"
        case studentPickupAddress = "student_pickup_address"
        case studentPickupLat = "student_pickup_lat"
        case studentPickupLng = "student_pickup_lng"
        case destinationLabel = "destination_label"
        case destinationAddress = "destination_address"
        case destinationLat = "destination_lat"
        case destinationLng = "destination_lng"
    }
}

private struct UpdateStudentParams: Encodable {
    let targetStudentID: UUID
    let studentNFCUID: String
    let studentFullName: String
    let studentDateOfBirth: String
    let studentPickupAddress: String
    let studentPickupLat: Double
    let studentPickupLng: Double

    enum CodingKeys: String, CodingKey {
        case targetStudentID = "target_student_id"
        case studentNFCUID = "student_nfc_uid"
        case studentFullName = "student_full_name"
        case studentDateOfBirth = "student_date_of_birth"
        case studentPickupAddress = "student_pickup_address"
        case studentPickupLat = "student_pickup_lat"
        case studentPickupLng = "student_pickup_lng"
    }
}

private struct LinkStudentParams: Encodable {
    let studentNFCUID: String

    enum CodingKeys: String, CodingKey {
        case studentNFCUID = "student_nfc_uid"
    }
}

private struct StudentIDParams: Encodable {
    let targetStudentID: UUID

    enum CodingKeys: String, CodingKey {
        case targetStudentID = "target_student_id"
    }
}

private struct StudentDuplicateCheckParams: Encodable {
    let studentFullName: String
    let studentDateOfBirth: String
    let excludeStudentID: UUID?

    enum CodingKeys: String, CodingKey {
        case studentFullName = "student_full_name"
        case studentDateOfBirth = "student_date_of_birth"
        case excludeStudentID = "exclude_student_id"
    }
}

private struct DestinationMutationParams: Encodable {
    let targetStudentID: UUID
    let destinationLabel: String
    let destinationAddress: String
    let destinationLat: Double
    let destinationLng: Double

    enum CodingKeys: String, CodingKey {
        case targetStudentID = "target_student_id"
        case destinationLabel = "destination_label"
        case destinationAddress = "destination_address"
        case destinationLat = "destination_lat"
        case destinationLng = "destination_lng"
    }
}

private struct DestinationUpdateParams: Encodable {
    let targetDestinationID: UUID
    let destinationLabel: String
    let destinationAddress: String
    let destinationLat: Double
    let destinationLng: Double

    enum CodingKeys: String, CodingKey {
        case targetDestinationID = "target_destination_id"
        case destinationLabel = "destination_label"
        case destinationAddress = "destination_address"
        case destinationLat = "destination_lat"
        case destinationLng = "destination_lng"
    }
}

private struct DestinationIDParams: Encodable {
    let targetDestinationID: UUID

    enum CodingKeys: String, CodingKey {
        case targetDestinationID = "target_destination_id"
    }
}

enum SupabaseStudentDirectoryService {
    static func fetchLinkedStudents() async throws -> [StudentDirectoryEntry] {
        let students: [StudentRecord] = try await supabase
            .from("students")
            .select("id, nfc_uid, full_name, date_of_birth, pickup_address, active")
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

    static func createStudent(from input: StudentEditorInput) async throws {
        let normalized = try normalize(input)
        try await ensureNoDuplicateStudentCandidate(
            fullName: normalized.fullName,
            dateOfBirth: normalized.dateOfBirth,
            excludingStudentID: nil
        )
        let pickup = try await geocodeAddress(normalized.pickupAddress)
        let primaryDestination = try await geocodeDestination(normalized.destinations[0])

        do {
            try await supabase
                .rpc(
                    "create_student_with_destination",
                    params: CreateStudentParams(
                        studentNFCUID: normalized.nfcUID,
                        studentFullName: normalized.fullName,
                        studentDateOfBirth: StudentDateCodec.stringify(normalized.dateOfBirth),
                        studentPickupAddress: pickup.formatted,
                        studentPickupLat: pickup.lat,
                        studentPickupLng: pickup.lng,
                        destinationLabel: primaryDestination.label,
                        destinationAddress: primaryDestination.formattedAddress,
                        destinationLat: primaryDestination.lat,
                        destinationLng: primaryDestination.lng
                    )
                )
                .execute()
        } catch {
            throw mapBackendStudentManagementError(error)
        }

        guard normalized.destinations.count > 1 else { return }

        let createdStudent = try await fetchStudent(matchingNFCUID: normalized.nfcUID)

        for destination in normalized.destinations.dropFirst() {
            try await addDestination(to: createdStudent.student.id, destination: destination)
        }
    }

    static func updateStudent(_ entry: StudentDirectoryEntry, from input: StudentEditorInput) async throws {
        let normalized = try normalize(input)
        let existingDestinationIDs = Set(entry.destinations.map(\ .id))
        let keptDestinationIDs = Set(normalized.destinations.compactMap(\ .destinationID))

        if shouldUpdateStudentRecord(entry.student, with: normalized) {
            try await ensureNoDuplicateStudentCandidate(
                fullName: normalized.fullName,
                dateOfBirth: normalized.dateOfBirth,
                excludingStudentID: entry.student.id
            )
            let pickup = try await geocodeAddress(normalized.pickupAddress)

            do {
                try await supabase
                    .rpc(
                        "update_student",
                        params: UpdateStudentParams(
                            targetStudentID: entry.student.id,
                            studentNFCUID: normalized.nfcUID,
                            studentFullName: normalized.fullName,
                            studentDateOfBirth: StudentDateCodec.stringify(normalized.dateOfBirth),
                            studentPickupAddress: pickup.formatted,
                            studentPickupLat: pickup.lat,
                            studentPickupLng: pickup.lng
                        )
                    )
                    .execute()
            } catch {
                throw mapBackendStudentManagementError(error)
            }
        }

        let originalDestinationsByID = Dictionary(uniqueKeysWithValues: entry.destinations.map { ($0.id, $0) })

        for destination in normalized.destinations {
            if let destinationID = destination.destinationID,
               let original = originalDestinationsByID[destinationID] {
                if destination.label != original.label || destination.address != original.address {
                    try await updateDestination(destinationID, destination: destination)
                }
            } else {
                try await addDestination(to: entry.student.id, destination: destination)
            }
        }

        let removedDestinationIDs = existingDestinationIDs.subtracting(keptDestinationIDs)
        for destinationID in removedDestinationIDs {
            try await deleteDestination(destinationID)
        }
    }

    static func archiveStudent(_ studentID: UUID) async throws {
        try await supabase
            .rpc("archive_student", params: StudentIDParams(targetStudentID: studentID))
            .execute()
    }

    static func linkStudent(byNFCUID nfcUID: String) async throws {
        let normalizedNFCUID = normalizeNFCUID(nfcUID)
        guard !normalizedNFCUID.isEmpty else {
            throw StudentManagementError.nfcUIDRequired
        }

        try await supabase
            .rpc("link_student_by_nfc", params: LinkStudentParams(studentNFCUID: normalizedNFCUID))
            .execute()
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

    private static func fetchStudent(matchingNFCUID nfcUID: String) async throws -> StudentDirectoryEntry {
        let entries = try await fetchLinkedStudents()
        guard let entry = entries.first(where: { normalizeNFCUID($0.student.nfcUID) == nfcUID }) else {
            throw StudentManagementError.createdStudentMissing
        }
        return entry
    }

    private static func addDestination(to studentID: UUID, destination: EditableDestination) async throws {
        let geocodedDestination = try await geocodeDestination(destination)

        do {
            try await supabase
                .rpc(
                    "add_destination",
                    params: DestinationMutationParams(
                        targetStudentID: studentID,
                        destinationLabel: geocodedDestination.label,
                        destinationAddress: geocodedDestination.formattedAddress,
                        destinationLat: geocodedDestination.lat,
                        destinationLng: geocodedDestination.lng
                    )
                )
                .execute()
        } catch {
            throw mapBackendStudentManagementError(error)
        }
    }

    private static func updateDestination(_ destinationID: UUID, destination: EditableDestination) async throws {
        let geocodedDestination = try await geocodeDestination(destination)

        do {
            try await supabase
                .rpc(
                    "update_destination",
                    params: DestinationUpdateParams(
                        targetDestinationID: destinationID,
                        destinationLabel: geocodedDestination.label,
                        destinationAddress: geocodedDestination.formattedAddress,
                        destinationLat: geocodedDestination.lat,
                        destinationLng: geocodedDestination.lng
                    )
                )
                .execute()
        } catch {
            throw mapBackendStudentManagementError(error)
        }
    }

    private static func deleteDestination(_ destinationID: UUID) async throws {
        try await supabase
            .rpc("delete_destination", params: DestinationIDParams(targetDestinationID: destinationID))
            .execute()
    }

    private static func normalize(_ input: StudentEditorInput) throws -> StudentEditorInput {
        let normalizedNFCUID = normalizeNFCUID(input.nfcUID)
        let normalizedFullName = input.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPickupAddress = input.pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestinations = input.destinations.map {
            EditableDestination(
                destinationID: $0.destinationID,
                label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                address: $0.address.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard !normalizedNFCUID.isEmpty else {
            throw StudentManagementError.nfcUIDRequired
        }

        guard !normalizedFullName.isEmpty else {
            throw StudentManagementError.fullNameRequired
        }

        guard !normalizedPickupAddress.isEmpty else {
            throw StudentManagementError.pickupAddressRequired
        }

        guard !normalizedDestinations.isEmpty else {
            throw StudentManagementError.destinationRequired
        }

        guard normalizedDestinations.allSatisfy({ !$0.label.isEmpty && !$0.address.isEmpty }) else {
            throw StudentManagementError.destinationIncomplete
        }

        var destinationKeys = Set<String>()
        for destination in normalizedDestinations {
            let key = makeDestinationKey(label: destination.label, address: destination.address)
            guard destinationKeys.insert(key).inserted else {
                throw StudentManagementError.duplicateDestination
            }
        }

        return StudentEditorInput(
            nfcUID: normalizedNFCUID,
            fullName: normalizedFullName,
            dateOfBirth: input.dateOfBirth,
            pickupAddress: normalizedPickupAddress,
            destinations: normalizedDestinations
        )
    }

    private static func normalizeNFCUID(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static func normalizeText(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func makeDestinationKey(label: String, address: String) -> String {
        "\(normalizeText(label))|\(normalizeText(address))"
    }

    private static func shouldUpdateStudentRecord(_ student: StudentRecord, with input: StudentEditorInput) -> Bool {
        normalizeNFCUID(student.nfcUID) != input.nfcUID
            || student.fullName != input.fullName
            || student.dateOfBirth != StudentDateCodec.stringify(input.dateOfBirth)
            || student.pickupAddress != input.pickupAddress
    }

    private static func ensureNoDuplicateStudentCandidate(
        fullName: String,
        dateOfBirth: Date,
        excludingStudentID: UUID?
    ) async throws {
        let duplicateExists: Bool

        do {
            duplicateExists = try await supabase
                .rpc(
                    "student_duplicate_exists",
                    params: StudentDuplicateCheckParams(
                        studentFullName: fullName,
                        studentDateOfBirth: StudentDateCodec.stringify(dateOfBirth),
                        excludeStudentID: excludingStudentID
                    )
                )
                .execute()
                .value
        } catch {
            throw mapBackendStudentManagementError(error)
        }

        if duplicateExists {
            throw StudentManagementError.duplicateStudent
        }
    }

    private static func mapBackendStudentManagementError(_ error: Error) -> Error {
        let message = error.localizedDescription.lowercased()

        if message.contains("student_duplicate_exists")
            && (message.contains("function") || message.contains("schema cache") || message.contains("pgrst")) {
            return StudentManagementError.databaseUpdateRequired
        }

        if message.contains("already linked to another active student") {
            return StudentManagementError.duplicateNFCUID
        }

        if message.contains("same name and date of birth already exists") {
            return StudentManagementError.duplicateStudent
        }

        if message.contains("already has that destination") {
            return StudentManagementError.duplicateDestination
        }

        return error
    }

    private static func geocodeAddress(_ address: String) async throws -> (lat: Double, lng: Double, formatted: String) {
        try await Geocoder.geocode(address)
    }

    private static func geocodeDestination(_ destination: EditableDestination) async throws -> (
        label: String,
        lat: Double,
        lng: Double,
        formattedAddress: String
    ) {
        let geocoded = try await Geocoder.geocode(destination.address)
        return (
            label: destination.label,
            lat: geocoded.lat,
            lng: geocoded.lng,
            formattedAddress: geocoded.formatted
        )
    }
}
