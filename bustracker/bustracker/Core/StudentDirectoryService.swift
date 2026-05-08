import Foundation
import Supabase

private struct CreateStudentParams: Encodable {
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
    let studentFullName: String
    let studentDateOfBirth: String
    let studentPickupAddress: String
    let studentPickupLat: Double
    let studentPickupLng: Double

    enum CodingKeys: String, CodingKey {
        case targetStudentID = "target_student_id"
        case studentFullName = "student_full_name"
        case studentDateOfBirth = "student_date_of_birth"
        case studentPickupAddress = "student_pickup_address"
        case studentPickupLat = "student_pickup_lat"
        case studentPickupLng = "student_pickup_lng"
    }
}

private struct LinkStudentParams: Encodable {
    let studentQRCode: String

    enum CodingKeys: String, CodingKey {
        case studentQRCode = "student_qr_code"
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

private struct CreatedStudentRow: Decodable {
    let id: UUID
    let qrCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case qrCode = "qr_code"
    }
}

enum SupabaseStudentDirectoryService {
    static func fetchLinkedStudents() async throws -> [StudentDirectoryEntry] {
        let students: [StudentRecord] = try await supabase
            .from("students")
            .select("id, qr_code, full_name, date_of_birth, pickup_address, active")
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

    @discardableResult
    static func createStudent(from input: StudentEditorInput) async throws -> CreatedStudent {
        let normalized = try normalize(input)
        try await ensureNoDuplicateStudentCandidate(
            fullName: normalized.fullName,
            dateOfBirth: normalized.dateOfBirth,
            excludingStudentID: nil
        )

        guard let pickup = normalized.pickupCoordinate else {
            throw StudentManagementError.pickupAddressRequired
        }
        guard let primary = normalized.destinations.first,
              let primaryCoord = primary.coordinate else {
            throw StudentManagementError.destinationIncomplete
        }

        let createdRows: [CreatedStudentRow]
        do {
            createdRows = try await supabase
                .rpc(
                    "create_student_with_destination",
                    params: CreateStudentParams(
                        studentFullName: normalized.fullName,
                        studentDateOfBirth: StudentDateCodec.stringify(normalized.dateOfBirth),
                        studentPickupAddress: normalized.pickupAddress,
                        studentPickupLat: pickup.latitude,
                        studentPickupLng: pickup.longitude,
                        destinationLabel: primary.label,
                        destinationAddress: primary.address,
                        destinationLat: primaryCoord.latitude,
                        destinationLng: primaryCoord.longitude
                    )
                )
                .execute()
                .value
        } catch {
            throw mapBackendStudentManagementError(error)
        }

        guard let createdRow = createdRows.first else {
            throw StudentManagementError.createdStudentMissing
        }

        let created = CreatedStudent(id: createdRow.id, qrCode: createdRow.qrCode)

        for destination in normalized.destinations.dropFirst() {
            try await addDestination(to: created.id, destination: destination)
        }

        return created
    }

    static func updateStudent(_ entry: StudentDirectoryEntry, from input: StudentEditorInput) async throws {
        let normalized = try normalize(input)
        let existingDestinationIDs = Set(entry.destinations.map(\ .id))
        let keptDestinationIDs = Set(normalized.destinations.compactMap(\ .destinationID))

        let nonPickupChanged = normalized.fullName != entry.student.fullName
            || StudentDateCodec.stringify(normalized.dateOfBirth) != entry.student.dateOfBirth
        let pickupChanged = normalized.pickupCoordinate != nil

        if nonPickupChanged || pickupChanged {
            try await ensureNoDuplicateStudentCandidate(
                fullName: normalized.fullName,
                dateOfBirth: normalized.dateOfBirth,
                excludingStudentID: entry.student.id
            )

            // If pickup wasn't re-picked, we still need lat/lng to satisfy the RPC contract.
            // Forward-geocode the saved address as a fallback. Most addresses we previously
            // saved came from reverse geocoding, so the round-trip almost always succeeds.
            let pickup: CoordinatePair
            if let picked = normalized.pickupCoordinate {
                pickup = picked
            } else {
                let geocoded = try await Geocoder.geocode(normalized.pickupAddress)
                pickup = CoordinatePair(latitude: geocoded.lat, longitude: geocoded.lng)
            }

            do {
                try await supabase
                    .rpc(
                        "update_student",
                        params: UpdateStudentParams(
                            targetStudentID: entry.student.id,
                            studentFullName: normalized.fullName,
                            studentDateOfBirth: StudentDateCodec.stringify(normalized.dateOfBirth),
                            studentPickupAddress: normalized.pickupAddress,
                            studentPickupLat: pickup.latitude,
                            studentPickupLng: pickup.longitude
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
                let labelChanged = destination.label != original.label
                let locationChanged = destination.coordinate != nil
                if labelChanged || locationChanged {
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

    static func linkStudent(byQRCode qrCode: String) async throws {
        let trimmed = qrCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StudentManagementError.qrCodeRequired
        }

        do {
            try await supabase
                .rpc("link_student_by_qr", params: LinkStudentParams(studentQRCode: trimmed))
                .execute()
        } catch {
            throw mapBackendStudentManagementError(error)
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

    private static func addDestination(to studentID: UUID, destination: EditableDestination) async throws {
        let resolved = try await resolveCoordinate(for: destination)

        do {
            try await supabase
                .rpc(
                    "add_destination",
                    params: DestinationMutationParams(
                        targetStudentID: studentID,
                        destinationLabel: destination.label,
                        destinationAddress: destination.address,
                        destinationLat: resolved.latitude,
                        destinationLng: resolved.longitude
                    )
                )
                .execute()
        } catch {
            throw mapBackendStudentManagementError(error)
        }
    }

    private static func updateDestination(_ destinationID: UUID, destination: EditableDestination) async throws {
        let resolved = try await resolveCoordinate(for: destination)

        do {
            try await supabase
                .rpc(
                    "update_destination",
                    params: DestinationUpdateParams(
                        targetDestinationID: destinationID,
                        destinationLabel: destination.label,
                        destinationAddress: destination.address,
                        destinationLat: resolved.latitude,
                        destinationLng: resolved.longitude
                    )
                )
                .execute()
        } catch {
            throw mapBackendStudentManagementError(error)
        }
    }

    /// For destinations that already exist in the DB and weren't re-picked in this session,
    /// we need lat/lng to satisfy the RPC contract. Forward-geocode the saved address as a
    /// fallback; freshly picked destinations skip this entirely.
    private static func resolveCoordinate(for destination: EditableDestination) async throws -> CoordinatePair {
        if let coordinate = destination.coordinate {
            return coordinate
        }
        let geocoded = try await Geocoder.geocode(destination.address)
        return CoordinatePair(latitude: geocoded.lat, longitude: geocoded.lng)
    }

    private static func deleteDestination(_ destinationID: UUID) async throws {
        try await supabase
            .rpc("delete_destination", params: DestinationIDParams(targetDestinationID: destinationID))
            .execute()
    }

    private static func normalize(_ input: StudentEditorInput) throws -> StudentEditorInput {
        let normalizedFullName = input.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPickupAddress = input.pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestinations = input.destinations.map {
            EditableDestination(
                destinationID: $0.destinationID,
                label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                address: $0.address.trimmingCharacters(in: .whitespacesAndNewlines),
                coordinate: $0.coordinate
            )
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
            fullName: normalizedFullName,
            dateOfBirth: input.dateOfBirth,
            pickupAddress: normalizedPickupAddress,
            pickupCoordinate: input.pickupCoordinate,
            destinations: normalizedDestinations
        )
    }

    private static func normalizeText(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func makeDestinationKey(label: String, address: String) -> String {
        "\(normalizeText(label))|\(normalizeText(address))"
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

        if message.contains("function") && message.contains("schema cache") {
            return StudentManagementError.databaseUpdateRequired
        }

        if message.contains("no active student matches") {
            return StudentManagementError.qrCodeNotFound
        }

        if message.contains("same name and date of birth already exists") {
            return StudentManagementError.duplicateStudent
        }

        if message.contains("already has that destination") {
            return StudentManagementError.duplicateDestination
        }

        return error
    }
}
