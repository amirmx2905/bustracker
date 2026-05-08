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
