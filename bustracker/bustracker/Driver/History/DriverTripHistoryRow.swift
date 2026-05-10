import SwiftUI

struct DriverTripHistoryRow: View {
    let trip: TripHistoryEntry
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 14) {
                headerRow
                studentsRow
                divider
                footerRow
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.neonBlue.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Circle().strokeBorder(Color.neonBlue.opacity(0.4), lineWidth: 1)
                    }
                Image(systemName: "bus.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.neonBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
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
    }

    private var studentsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.footnote)
                .foregroundStyle(Color.neonBlue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(studentCountLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if !trip.studentNames.isEmpty {
                    Text(trip.studentNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.appBorder.opacity(0.6))
            .frame(height: 1)
    }

    private var footerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.caption2)
                .foregroundStyle(Color.appSecondary)
            Text("\(trip.eventCount) event\(trip.eventCount == 1 ? "" : "s") recorded")
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
            Spacer()
            Text("View route")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.neonBlue)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.neonBlue)
        }
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if Calendar.current.isDateInToday(trip.endedAt) { return "Today" }
        if Calendar.current.isDateInYesterday(trip.endedAt) { return "Yesterday" }
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

    private var studentCountLabel: String {
        let count = trip.studentNames.count
        if count == 0 { return "No scans recorded" }
        return "\(count) student\(count == 1 ? "" : "s")"
    }
}
