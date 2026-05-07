import CoreLocation
import MapKit
import SwiftUI

struct LocatedAddress: Equatable {
    var latitude: Double
    var longitude: Double
    var address: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct LocationPickerSheet: View {
    let title: String
    let initialCenter: CLLocationCoordinate2D
    let onPicked: (LocatedAddress) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition
    @State private var lastVisibleCenter: CLLocationCoordinate2D
    @State private var lastVisibleRegion: MKCoordinateRegion?
    @State private var resolvedAddress: String = ""
    @State private var isResolving = false
    @State private var resolveTask: Task<Void, Never>?
    @State private var searchQuery: String = ""
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isLocatingUser = false
    @State private var hasLocatedUserOnce = false

    init(
        title: String,
        initialCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(
            latitude: 20.6597,
            longitude: -103.3496
        ),
        onPicked: @escaping (LocatedAddress) -> Void
    ) {
        self.title = title
        self.initialCenter = initialCenter
        self.onPicked = onPicked

        let region = MKCoordinateRegion(
            center: initialCenter,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        _cameraPosition = State(initialValue: .region(region))
        _lastVisibleCenter = State(initialValue: initialCenter)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition)
                    .ignoresSafeArea()
                    .onMapCameraChange(frequency: .onEnd) { context in
                        lastVisibleCenter = context.region.center
                        lastVisibleRegion = context.region
                        scheduleResolve()
                    }

                centerPin

                VStack(spacing: 12) {
                    searchBar
                    if let searchError {
                        InlineMessage(
                            message: searchError,
                            color: .orange,
                            icon: "exclamationmark.triangle.fill"
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        locateMeButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    confirmCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
            .background(Color.appBg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.neonBlue)
                }
            }
            .task {
                await locateUserIfPossible(animated: false)
                await resolveCenter()
            }
            .onDisappear { resolveTask?.cancel() }
        }
    }

    private var locateMeButton: some View {
        Button {
            Task { await locateUserIfPossible(animated: true) }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.appCard)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle().strokeBorder(Color.appBorder, lineWidth: 1)
                    }
                if isLocatingUser {
                    ProgressView().tint(.neonBlue)
                } else {
                    Image(systemName: "scope")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.neonBlue)
                }
            }
        }
        .disabled(isLocatingUser)
    }

    private var centerPin: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Color.neonBlue)
                .neonGlow(inner: 6, outer: 12)
            Circle()
                .fill(Color.neonBlue.opacity(0.85))
                .frame(width: 8, height: 8)
        }
        .offset(y: -19)
        .allowsHitTesting(false)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appSecondary)

            TextField("Search address or place", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
                .foregroundStyle(.white)

            if isSearching {
                ProgressView().tint(.neonBlue)
            } else if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appCard.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private var confirmCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Color.neonBlue)
                    .font(.headline)

                if isResolving && resolvedAddress.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().tint(.neonBlue)
                        Text("Locating...")
                            .font(.subheadline)
                            .foregroundStyle(Color.appSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(resolvedAddress.isEmpty ? "Drag the map to set the location." : resolvedAddress)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button {
                confirm()
            } label: {
                Text("Use this location")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonPrimaryButtonStyle())
            .disabled(resolvedAddress.isEmpty)
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
        .shadow(radius: 12)
    }

    private func locateUserIfPossible(animated: Bool) async {
        if isLocatingUser { return }
        isLocatingUser = true
        defer { isLocatingUser = false }

        let fetcher = CurrentLocationFetcher()
        guard let location = await fetcher.fetch() else {
            return
        }

        let coordinate = location.coordinate
        lastVisibleCenter = coordinate
        hasLocatedUserOnce = true

        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )

        if animated {
            withAnimation(.easeInOut(duration: 0.4)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }

        scheduleResolve()
    }

    private func scheduleResolve() {
        resolveTask?.cancel()
        resolveTask = Task { await resolveCenter() }
    }

    private func resolveCenter() async {
        let target = lastVisibleCenter
        await MainActor.run { isResolving = true }

        let result = await reverseGeocode(target)

        if Task.isCancelled { return }

        await MainActor.run {
            isResolving = false
            if let result {
                resolvedAddress = result
            }
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first.flatMap(formatPlacemark)
        } catch {
            return nil
        }
    }

    private func formatPlacemark(_ placemark: CLPlacemark) -> String? {
        var parts: [String] = []

        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        if !street.isEmpty { parts.append(street) }

        if let locality = placemark.locality { parts.append(locality) }
        if let area = placemark.administrativeArea { parts.append(area) }
        if let postal = placemark.postalCode, !postal.isEmpty {
            if let last = parts.last {
                parts[parts.count - 1] = "\(last) \(postal)"
            } else {
                parts.append(postal)
            }
        }
        if let country = placemark.country { parts.append(country) }

        let formatted = parts.joined(separator: ", ")
        return formatted.isEmpty ? nil : formatted
    }

    private func runSearch() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            isSearching = true
            searchError = nil
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let lastVisibleRegion {
            request.region = lastVisibleRegion
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                await MainActor.run {
                    isSearching = false
                    searchError = "No matching address found."
                }
                return
            }

            await MainActor.run {
                let coord = item.placemark.coordinate
                lastVisibleCenter = coord
                cameraPosition = .region(MKCoordinateRegion(
                    center: coord,
                    latitudinalMeters: 600,
                    longitudinalMeters: 600
                ))
                isSearching = false
                searchError = nil
            }

            scheduleResolve()
        } catch {
            await MainActor.run {
                isSearching = false
                searchError = error.localizedDescription
            }
        }
    }

    private func confirm() {
        guard !resolvedAddress.isEmpty else { return }
        let result = LocatedAddress(
            latitude: lastVisibleCenter.latitude,
            longitude: lastVisibleCenter.longitude,
            address: resolvedAddress
        )
        onPicked(result)
        dismiss()
    }
}
