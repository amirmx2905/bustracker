import SwiftUI

struct TripHistoryRow: View {
    let trip: TripHistoryEntry
    let onOpen: () -> Void
    let onHide: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayLabel)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(timeRangeLabel)
                            .font(.caption)
                            .foregroundStyle(Color.appSecondary)
                    }
                    Spacer()
                    durationBadge
                }

                infoRow(
                    icon: "person.2.fill",
                    label: "Students",
                    value: trip.studentNames.isEmpty ? "—" : trip.studentNames.joined(separator: ", ")
                )

                HStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.caption2)
                    Text("\(trip.eventCount) event\(trip.eventCount == 1 ? "" : "s") · tap to view route")
                }
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onHide) {
                Label("Hide from history", systemImage: "eye.slash")
            }
        }
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if Calendar.current.isDateInToday(trip.endedAt) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(trip.endedAt) {
            return "Yesterday"
        }
        return formatter.string(from: trip.endedAt)
    }

    private var timeRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(formatter.string(from: trip.startedAt)) → \(formatter.string(from: trip.endedAt))"
    }

    private var durationBadge: some View {
        Text(durationLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.neonBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.neonBlue.opacity(0.15), in: Capsule())
    }

    private var durationLabel: String {
        let interval = trip.endedAt.timeIntervalSince(trip.startedAt)
        let minutes = max(0, Int(interval / 60))
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours) h" : "\(hours)h \(remaining)m"
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.neonBlue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
    }
}
