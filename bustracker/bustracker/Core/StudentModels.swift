import Foundation

struct StudentRecord: Decodable, Identifiable {
    let id: UUID
    let qrCode: String
    let fullName: String
    let dateOfBirth: String
    let pickupAddress: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case qrCode = "qr_code"
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

struct CoordinatePair: Equatable {
    var latitude: Double
    var longitude: Double
}

struct EditableDestination: Identifiable, Equatable {
    let id: UUID
    let destinationID: UUID?
    var label: String
    /// Address text shown to the user. Filled in by the location picker for new destinations,
    /// or by the DB load for existing ones.
    var address: String
    /// Coordinates of the user-picked map pin. nil for existing destinations whose pin has not
    /// been re-picked in this edit session.
    var coordinate: CoordinatePair?

    init(destinationID: UUID? = nil, label: String = "", address: String = "", coordinate: CoordinatePair? = nil) {
        self.id = UUID()
        self.destinationID = destinationID
        self.label = label
        self.address = address
        self.coordinate = coordinate
    }

    init(record: DestinationRecord) {
        self.id = UUID()
        self.destinationID = record.id
        self.label = record.label
        self.address = record.address
        self.coordinate = nil
    }

    var hasLocation: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct StudentEditorInput {
    let fullName: String
    let dateOfBirth: Date
    /// Pickup address text. For an unchanged existing student, this is the saved address.
    /// For a freshly picked location, it is the reverse-geocoded address from the picker.
    let pickupAddress: String
    /// Coordinates of the freshly picked pickup pin. nil when editing a student whose pickup
    /// hasn't been re-picked in this session.
    let pickupCoordinate: CoordinatePair?
    let destinations: [EditableDestination]
}

struct CreatedStudent {
    let id: UUID
    let qrCode: String
}

enum StudentManagementError: LocalizedError {
    case qrCodeRequired
    case qrCodeNotFound
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
        case .qrCodeRequired:
            return "Scan or enter a QR code before linking the student."
        case .qrCodeNotFound:
            return "No active student matches that QR code."
        case .fullNameRequired:
            return "Student name is required."
        case .pickupAddressRequired:
            return "Pickup address is required."
        case .destinationRequired:
            return "Students must have at least one destination."
        case .destinationIncomplete:
            return "Every destination needs both a label and an address."
        case .duplicateStudent:
            return "An active student with the same name and date of birth already exists. Use Link by QR or manage the existing student instead."
        case .duplicateDestination:
            return "This student already has that destination. Remove the duplicate or change its label/address."
        case .databaseUpdateRequired:
            return "The database is missing the latest QR-aware RPCs. Re-run supabase/sql/functions.sql and try again."
        case .createdStudentMissing:
            return "The student was created, but the app could not refresh its data. Pull to refresh and try again."
        }
    }
}

enum StudentDateCodec {
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
