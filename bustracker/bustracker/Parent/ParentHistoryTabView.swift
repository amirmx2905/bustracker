import CoreLocation
import MapKit
import SwiftUI

struct ParentHistoryTabView: View {
    @State private var trips: [TripHistoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTrip: TripHistoryEntry?
    @State private var pendingHideTrip: TripHistoryEntry?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let errorMessage, trips.isEmpty {
                        InlineMessage(
                            message: errorMessage,
                            color: .red,
                            icon: "exclamationmark.circle.fill"
                        )
                    }

                    if isLoading && trips.isEmpty {
                        loadingCard
                    } else if trips.isEmpty {
                        emptyCard
                    } else {
                        if let errorMessage {
                            InlineMessage(
                                message: errorMessage,
                                color: .orange,
                                icon: "exclamationmark.triangle.fill"
                            )
                        }

                        ForEach(trips) { trip in
                            TripHistoryRow(
                                trip: trip,
                                onOpen: { selectedTrip = trip },
                                onHide: { pendingHideTrip = trip }
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.appBg.ignoresSafeArea())
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await loadTrips() }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $selectedTrip) { trip in
                TripHistoryDetailView(trip: trip) {
                    await loadTrips()
                }
            }
            .alert(
                "Hide this trip?",
                isPresented: Binding(
                    get: { pendingHideTrip != nil },
                    set: { if !$0 { pendingHideTrip = nil } }
                ),
                presenting: pendingHideTrip
            ) { trip in
                Button("Cancel", role: .cancel) { }
                Button("Hide", role: .destructive) {
                    Task { await hide(trip: trip) }
                }
            } message: { _ in
                Text("This trip will stop showing up in your history. Other parents and the driver still see it.")
            }
            .task {
                guard trips.isEmpty, errorMessage == nil else { return }
                await loadTrips()
            }
        }
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.neonBlue)
            Text("Loading past trips...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.neonBlue)

            VStack(spacing: 4) {
                Text("No history yet")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Once a driver finishes a trip your students were on, you'll see it here.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    @MainActor
    private func loadTrips() async {
        isLoading = true
        defer { isLoading = false }
        do {
            trips = try await SupabaseParentHistoryService.fetchTripHistory()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func hide(trip: TripHistoryEntry) async {
        pendingHideTrip = nil
        do {
            try await SupabaseParentHistoryService.hideTrip(tripID: trip.tripID)
            trips.removeAll { $0.tripID == trip.tripID }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TripHistoryRow: View {
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

private struct TripHistoryDetailView: View {
    let trip: TripHistoryEntry
    let onHidden: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var path: [TripPositionLatLng] = []
    @State private var events: [TripHistoryEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showHideConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(.neonBlue)
                } else if let errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.orange)
                        Text("Couldn't load this trip")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.appSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Retry") {
                            Task { await load() }
                        }
                        .buttonStyle(NeonOutlineButtonStyle())
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Trip details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.neonBlue)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showHideConfirm = true
                        } label: {
                            Label("Hide from history", systemImage: "eye.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.neonBlue)
                    }
                }
            }
            .alert("Hide this trip?", isPresented: $showHideConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Hide", role: .destructive) {
                    Task { await hide() }
                }
            } message: {
                Text("This trip will stop showing up in your history.")
            }
            .task { await load() }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            mapSection
                .frame(maxWidth: .infinity)
                .frame(height: 320)

            eventsList
        }
    }

    private var mapSection: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                if path.count >= 2 {
                    MapPolyline(coordinates: path.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                    })
                    .stroke(Color.neonBlue.opacity(0.85), lineWidth: 4)
                }

                if let start = path.first {
                    Annotation(
                        "Start",
                        coordinate: CLLocationCoordinate2D(latitude: start.lat, longitude: start.lng)
                    ) {
                        endpointMarker(symbol: "play.fill", color: .green)
                    }
                }

                if let end = path.last, path.count >= 2 {
                    Annotation(
                        "End",
                        coordinate: CLLocationCoordinate2D(latitude: end.lat, longitude: end.lng)
                    ) {
                        endpointMarker(symbol: "flag.checkered", color: .red)
                    }
                }

                ForEach(events.filter { $0.lat != nil && $0.lng != nil && ($0.eventType == "check_in" || $0.eventType == "check_out") }) { event in
                    Annotation(
                        event.studentName ?? "",
                        coordinate: CLLocationCoordinate2D(latitude: event.lat ?? 0, longitude: event.lng ?? 0)
                    ) {
                        eventMarker(for: event)
                    }
                }
            }
            .ignoresSafeArea(edges: .horizontal)

            if path.count < 2 {
                pathFallback
                    .padding(12)
            }
        }
    }

    private var pathFallback: some View {
        Text("No GPS path was recorded for this trip.")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.neonBlue.opacity(0.4), lineWidth: 1)
            }
    }

    private var eventsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summaryCard

                if events.isEmpty {
                    Text("No events for your students on this trip.")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondary)
                        .padding(.top, 8)
                } else {
                    Text("EVENTS")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.appSecondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)

                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trip.studentNames.joined(separator: ", "))
                .font(.headline)
                .foregroundStyle(.white)
            HStack(spacing: 14) {
                Label(formattedRange, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private var formattedRange: String {
        let day = DateFormatter()
        day.dateStyle = .medium
        day.timeStyle = .none
        let time = DateFormatter()
        time.dateStyle = .none
        time.timeStyle = .short
        return "\(day.string(from: trip.endedAt)) · \(time.string(from: trip.startedAt)) → \(time.string(from: trip.endedAt))"
    }

    private func eventRow(_ event: TripHistoryEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: event.eventType))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color(for: event.eventType))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label(for: event.eventType))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(event.studentName ?? "—") · \(timeOnly(event.occurredAt))")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1)
        }
    }

    private func endpointMarker(symbol: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .shadow(color: color.opacity(0.6), radius: 8)
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private func eventMarker(for event: TripHistoryEvent) -> some View {
        ZStack {
            Circle()
                .fill(color(for: event.eventType))
                .frame(width: 22, height: 22)
            Image(systemName: icon(for: event.eventType))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "check_in": return "arrow.down.to.line"
        case "check_out": return "arrow.up.from.line"
        case "destination_enter": return "flag.checkered"
        case "destination_exit": return "flag.slash"
        case "pickup_proximity": return "figure.walk"
        default: return "questionmark.circle"
        }
    }

    private func color(for type: String) -> Color {
        switch type {
        case "check_in": return .green
        case "check_out": return .neonBlue
        case "destination_enter": return .orange
        case "destination_exit": return .yellow
        case "pickup_proximity": return .purple
        default: return .gray
        }
    }

    private func label(for type: String) -> String {
        switch type {
        case "check_in": return "Boarded"
        case "check_out": return "Got off"
        case "destination_enter": return "Arrived at destination"
        case "destination_exit": return "Left destination"
        case "pickup_proximity": return "Near pickup"
        default: return type
        }
    }

    private func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let pathFetch = SupabaseParentHistoryService.fetchTripPath(tripID: trip.tripID)
            async let eventsFetch = SupabaseParentHistoryService.fetchTripEvents(tripID: trip.tripID)
            let (loadedPath, loadedEvents) = try await (pathFetch, eventsFetch)
            path = loadedPath
            events = loadedEvents
            recenter()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func recenter() {
        let coords = path.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }

        guard !coords.isEmpty else { return }

        if coords.count == 1 {
            let region = MKCoordinateRegion(
                center: coords[0],
                latitudinalMeters: 700,
                longitudinalMeters: 700
            )
            cameraPosition = .region(region)
            return
        }

        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.005, (maxLng - minLng) * 1.4)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    @MainActor
    private func hide() async {
        do {
            try await SupabaseParentHistoryService.hideTrip(tripID: trip.tripID)
            await onHidden()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
