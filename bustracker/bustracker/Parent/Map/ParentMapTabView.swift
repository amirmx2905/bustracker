import Combine
import CoreLocation
import MapKit
import SwiftUI

/// One full-screen live map showing every active trip a parent has a student on.
/// Each trip gets one bus annotation (positioned at the latest GPS point) plus a
/// neon polyline tracing where it has been so far.
struct ParentMapTabView: View {
    @State private var activeTrips: [ActiveTripForParent] = []
    @State private var pathsByTrip: [UUID: [TripPositionLatLng]] = [:]
    @State private var liveTripError: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    private let livePollInterval: TimeInterval = 10

    private struct TripGroup: Identifiable {
        let tripID: UUID
        let studentNames: [String]
        let path: [TripPositionLatLng]
        let checkInAt: Date

        var id: UUID { tripID }
        var latest: TripPositionLatLng? { path.last }
    }

    private var groupedTrips: [TripGroup] {
        let grouped = Dictionary(grouping: activeTrips) { $0.tripID }
        return grouped.map { tripID, trips in
            TripGroup(
                tripID: tripID,
                studentNames: trips.map(\.studentName),
                path: pathsByTrip[tripID] ?? [],
                checkInAt: trips.map(\.checkInAt).min() ?? Date()
            )
        }
        .sorted { $0.checkInAt > $1.checkInAt }
    }

    private var totalStudents: Int { activeTrips.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                if !groupedTrips.isEmpty {
                    mapView
                    floatingHeader
                } else if let liveTripError {
                    errorState(message: liveTripError)
                } else {
                    emptyState
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await refreshActiveTrips()
            }
            .onReceive(Timer.publish(every: livePollInterval, on: .main, in: .common).autoconnect()) { _ in
                Task { await refreshActiveTrips() }
            }
        }
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            ForEach(groupedTrips) { group in
                if group.path.count >= 2 {
                    MapPolyline(coordinates: group.path.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                    })
                    .stroke(Color.neonBlue.opacity(0.8), lineWidth: 4)
                }
                if let latest = group.latest {
                    Annotation(
                        group.studentNames.joined(separator: ", "),
                        coordinate: CLLocationCoordinate2D(latitude: latest.lat, longitude: latest.lng)
                    ) {
                        BusAnnotation(students: group.studentNames)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: pathsByTrip) {
            recenter()
        }
        .onAppear { recenter() }
    }

    private var floatingHeader: some View {
        VStack {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.neonBlue)
                    .frame(width: 10, height: 10)
                    .neonGlow(inner: 4, outer: 8)
                Text("\(totalStudents) on the bus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                if let updated = mostRecentUpdate {
                    Text("· updated \(relative(updated))")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                }
                Spacer()
                Button {
                    recenter()
                } label: {
                    Image(systemName: "scope")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.neonBlue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.neonBlue.opacity(0.45), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.neonBlue.opacity(0.08))
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)
                Circle()
                    .fill(Color.neonBlue.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "bus.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.neonBlue)
                    .neonGlow()
            }

            VStack(spacing: 6) {
                Text("Nobody's on the bus")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Once a driver checks in one of your students, you'll see the bus moving here in real time.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.orange)
            Text("Couldn't refresh live trips")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                Task { await refreshActiveTrips() }
            }
            .buttonStyle(NeonOutlineButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var mostRecentUpdate: Date? {
        groupedTrips.compactMap(\.latest?.recordedAt).max()
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func recenter() {
        let coords = groupedTrips.compactMap { $0.latest }.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        }

        guard !coords.isEmpty else { return }

        if coords.count == 1 {
            let region = MKCoordinateRegion(
                center: coords[0],
                latitudinalMeters: 700,
                longitudinalMeters: 700
            )
            withAnimation(.easeInOut(duration: 0.45)) {
                cameraPosition = .region(region)
            }
            return
        }

        // Fit all bus positions plus the full path of each trip in view.
        var allLats: [Double] = []
        var allLngs: [Double] = []
        for group in groupedTrips {
            for point in group.path {
                allLats.append(point.lat)
                allLngs.append(point.lng)
            }
        }
        guard let minLat = allLats.min(), let maxLat = allLats.max(),
              let minLng = allLngs.min(), let maxLng = allLngs.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.005, (maxLng - minLng) * 1.4)
        )
        withAnimation(.easeInOut(duration: 0.45)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    @MainActor
    private func refreshActiveTrips() async {
        do {
            let trips = try await SupabaseParentLiveTripService.fetchActiveTrips()
            activeTrips = trips
            liveTripError = nil

            let activeIDs = Set(trips.map(\.tripID))
            pathsByTrip = pathsByTrip.filter { activeIDs.contains($0.key) }

            await withTaskGroup(of: (UUID, [TripPositionLatLng]?).self) { group in
                for tripID in activeIDs {
                    group.addTask {
                        let path = try? await SupabaseParentLiveTripService.fetchPositionPath(tripID: tripID)
                        return (tripID, path)
                    }
                }
                for await (tripID, path) in group {
                    if let path, !path.isEmpty {
                        pathsByTrip[tripID] = path
                    }
                }
            }
        } catch {
            liveTripError = error.localizedDescription
        }
    }
}

private struct BusAnnotation: View {
    let students: [String]

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.neonBlue)
                    .frame(width: 38, height: 38)
                    .neonGlow(inner: 6, outer: 14)
                Image(systemName: "bus.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            Text(students.joined(separator: ", "))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.neonBlue.opacity(0.4), lineWidth: 1)
                }
        }
    }
}
