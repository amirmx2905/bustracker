import Combine
import SwiftUI

struct TripStatusCard: View {
    let tracker: TripTrackingManager
    let startedAt: Date
    @Binding var expanded: Bool

    @State private var tick = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.toggle()
            }
        } label: {
            VStack(spacing: 12) {
                HStack {
                    statusBadge
                    Spacer()
                    Text(elapsedString)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                        .padding(.leading, 4)
                }

                if expanded {
                    Divider().background(Color.appBorder)
                    statRow(label: "Positions pushed", value: "\(tracker.positionsPushed)")
                    statRow(label: "GPS gaps", value: "\(tracker.gapsRecorded)")
                    statRow(
                        label: "Last push",
                        value: tracker.lastPushAt.map { lastPushString(date: $0) } ?? "—"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.neonBlue.opacity(0.6), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tick.toggle()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.neonBlue)
                .frame(width: 10, height: 10)
                .neonGlow(inner: 4, outer: 8)
            Text("LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    private var elapsedString: String {
        _ = tick
        let interval = max(0, Int(Date().timeIntervalSince(startedAt)))
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        let seconds = interval % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func lastPushString(date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
