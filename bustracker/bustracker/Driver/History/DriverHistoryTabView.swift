import SwiftUI

struct DriverHistoryTabView: View {
    @State private var trips: [TripHistoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTrip: TripHistoryEntry?

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
                            DriverTripHistoryRow(trip: trip) {
                                selectedTrip = trip
                            }
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
                DriverTripDetailView(trip: trip)
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
                Text("No trips yet")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Trips you finish will show up here with their full route and scan log.")
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
            trips = try await SupabaseDriverHistoryService.fetchTripHistory()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
