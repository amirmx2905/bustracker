import SwiftUI

enum TripEventStyling {
    static func icon(for type: String) -> String {
        switch type {
        case "check_in": return "arrow.down.to.line"
        case "check_out": return "arrow.up.from.line"
        case "destination_enter": return "flag.checkered"
        case "destination_exit": return "flag.slash"
        case "pickup_proximity": return "figure.walk"
        default: return "questionmark.circle"
        }
    }

    static func color(for type: String) -> Color {
        switch type {
        case "check_in": return .green
        case "check_out": return .neonBlue
        case "destination_enter": return .orange
        case "destination_exit": return .yellow
        case "pickup_proximity": return .purple
        default: return .gray
        }
    }

    static func label(for type: String) -> String {
        switch type {
        case "check_in": return "Boarded"
        case "check_out": return "Got off"
        case "destination_enter": return "Arrived at destination"
        case "destination_exit": return "Left destination"
        case "pickup_proximity": return "Near pickup"
        default: return type
        }
    }

    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
