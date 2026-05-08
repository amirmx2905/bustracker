import CoreLocation
import MapKit
import SwiftUI

struct TripHistoryDetailView: View {
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
            Image(systemName: TripEventStyling.icon(for: event.eventType))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TripEventStyling.color(for: event.eventType))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(TripEventStyling.label(for: event.eventType))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(event.studentName ?? "—") · \(TripEventStyling.formatTime(event.occurredAt))")
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
                .fill(TripEventStyling.color(for: event.eventType))
                .frame(width: 22, height: 22)
            Image(systemName: TripEventStyling.icon(for: event.eventType))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
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
