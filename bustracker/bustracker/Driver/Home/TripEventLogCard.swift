import SwiftUI

struct TripEventLogCard: View {
    let events: [TripEventLogEntry]
    let isLoading: Bool
    @Binding var expanded: Bool
    let onRefresh: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(Color.neonBlue)
                    Text("Trip log")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    if !events.isEmpty {
                        Text("\(events.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.neonBlue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.neonBlue.opacity(0.2), in: Capsule())
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().tint(.neonBlue).controlSize(.small)
                    }
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().background(Color.appBorder)

                HStack {
                    Spacer()
                    Button {
                        Task { await onRefresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(Color.neonBlue)
                    }
                }

                if events.isEmpty {
                    Text("No scans yet. Hold a student's QR in front of the camera.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(events) { entry in
                                eventLogRow(entry: entry)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private func eventLogRow(entry: TripEventLogEntry) -> some View {
        let icon: String
        let color: Color
        let primary: String
        let secondary: String

        switch entry.type {
        case "check_in":
            icon = "person.fill.checkmark"
            color = .green
            primary = entry.studentName ?? "Unknown student"
            secondary = "Boarded the bus"
        case "check_out":
            icon = "person.fill.xmark"
            color = .neonBlue
            primary = entry.studentName ?? "Unknown student"
            secondary = "Got off the bus"
        default:
            icon = "questionmark.circle.fill"
            color = .orange
            primary = "Unknown QR"
            let payload = entry.rawQrPayload ?? ""
            secondary = payload.isEmpty
                ? "Not linked to any active student"
                : "Code: \(String(payload.prefix(12)))…"
        }

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(primary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(eventTimeString(entry.occurredAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.appSecondary)
        }
        .padding(.vertical, 4)
    }

    private func eventTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
