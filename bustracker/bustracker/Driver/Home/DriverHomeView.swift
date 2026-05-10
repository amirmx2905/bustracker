import AVFoundation
import Combine
import SwiftUI

struct DriverHomeView: View {
    let profile: Profile

    @State private var tracker = TripTrackingManager()
    @State private var permissionPrompted = false
    @State private var scanInProgress = false
    @State private var scanError: String?
    @State private var scanFeedback: ScanFeedback?
    @State private var eventLog: [TripEventLogEntry] = []
    @State private var isLoadingLog = false
    @State private var statusExpanded = false
    @State private var logExpanded = false
    @State private var cameraAuthorized = false

    private struct ScanFeedback: Identifiable {
        let id = UUID()
        let outcome: ScanOutcome
        let timestamp: Date
    }

    var body: some View {
        NavigationStack {
            Group {
                if isTripActive {
                    activeTripLayout
                } else {
                    idleLayout
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(isTripActive ? .hidden : .visible, for: .tabBar)
            .task {
                cameraAuthorized = QRScanner.authorizationStatus() == .authorized
                await tracker.resumeIfTripExists()
                if isTripActive { await refreshEventLog() }
            }
            .onChange(of: tracker.state) { _, newState in
                if case .active = newState {
                    Task { await refreshEventLog() }
                } else if case .idle = newState {
                    eventLog = []
                }
            }
            .onAppear { tracker.refreshPermission() }
        }
    }

    // MARK: - Layouts

    private var idleLayout: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            switch tracker.permissionStatus {
            case .always, .foregroundOnly:
                DriverIdleHero(
                    title: "Ready to roll",
                    subtitle: "Start a trip when the bus is ready to leave. The app will keep reporting GPS until you end it."
                ) {
                    VStack(spacing: 12) {
                        if let error = tracker.lastError {
                            InlineMessage(
                                message: error,
                                color: .red,
                                icon: "exclamationmark.circle.fill"
                            )
                        }
                        actionButton
                    }
                }
            case .denied, .restricted:
                DriverIdleHero(
                    title: "Location is disabled",
                    subtitle: "Open Settings → BusTracker → Location and pick 'While Using the App' or higher."
                ) {
                    Button("Open Settings") { handlePermissionTap() }
                        .buttonStyle(NeonOutlineButtonStyle())
                }
            case .unknown:
                DriverIdleHero(
                    title: "Location permission needed",
                    subtitle: "BusTracker reports GPS while a trip is active so parents can see the bus."
                ) {
                    Button("Allow location") { handlePermissionTap() }
                        .buttonStyle(NeonOutlineButtonStyle())
                }
            }
        }
    }

    private var activeTripLayout: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera fills the screen behind the overlay UI.
            if cameraAuthorized {
                QRScannerView(
                    onScan: { code in
                        Task { await processScan(code) }
                    },
                    onError: { error in
                        scanError = error.localizedDescription
                    },
                    rearmAfter: 2.5
                )
                .ignoresSafeArea()
            } else {
                cameraPermissionRequest
                    .padding(.horizontal, 20)
            }

            VStack(spacing: 12) {
                if case .active(_, let startedAt) = tracker.state {
                    TripStatusCard(
                        tracker: tracker,
                        startedAt: startedAt,
                        expanded: $statusExpanded
                    )
                }

                if let error = tracker.lastError {
                    InlineMessage(
                        message: error,
                        color: .red,
                        icon: "exclamationmark.circle.fill"
                    )
                }

                if let feedback = scanFeedback {
                    scanFeedbackBanner(feedback)
                }

                if let scanError {
                    InlineMessage(
                        message: scanError,
                        color: .red,
                        icon: "exclamationmark.circle.fill"
                    )
                }

                Spacer()

                let logCard = TripEventLogCard(
                    events: eventLog,
                    isLoading: isLoadingLog,
                    expanded: $logExpanded,
                    onRefresh: { await refreshEventLog() }
                )

                if logExpanded {
                    logCard.frame(maxHeight: 260)
                } else {
                    logCard
                }

                actionButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch tracker.state {
        case .idle, .starting:
            Button {
                Task { await tracker.startTrip() }
            } label: {
                HStack(spacing: 10) {
                    if case .starting = tracker.state {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(tracker.state == .starting ? "Starting…" : "Start trip")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonPrimaryButtonStyle())
            .disabled(!canStart)

        case .active, .ending:
            Button(role: .destructive) {
                Task { await tracker.endTrip() }
            } label: {
                HStack(spacing: 10) {
                    if case .ending = tracker.state {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "stop.fill")
                    }
                    Text(tracker.state == .ending ? "Ending…" : "End trip")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonOutlineButtonStyle())
            .disabled(tracker.state == .ending)
        }
    }

    // MARK: - Helpers

    private var isTripActive: Bool {
        if case .active = tracker.state { return true }
        if case .starting = tracker.state { return true }
        if case .ending = tracker.state { return true }
        return false
    }

    private var canStart: Bool {
        switch tracker.state {
        case .idle:
            return tracker.permissionStatus == .always || tracker.permissionStatus == .foregroundOnly
        default:
            return false
        }
    }

    private func handlePermissionTap() {
        switch tracker.permissionStatus {
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            Task { await tracker.requestPermissions() }
        }
    }

    // MARK: - Scan UI

    private var cameraPermissionRequest: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(Color.neonBlue)
                Text("Camera access needed")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            Text("BusTracker uses the camera to scan student QR codes during the trip. Tap to allow.")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
            Button("Allow camera") {
                Task {
                    let granted = await QRScanner.requestAuthorization()
                    cameraAuthorized = granted
                    if !granted {
                        scanError = QRScannerError.permissionDenied.localizedDescription
                    }
                }
            }
            .buttonStyle(NeonPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private func scanFeedbackBanner(_ feedback: ScanFeedback) -> some View {
        let color = colorFor(tone: feedback.outcome.tone)
        return HStack(spacing: 12) {
            Image(systemName: feedback.outcome.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
            Text(feedback.outcome.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(14)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(color.opacity(0.5), lineWidth: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func colorFor(tone: ScanFeedbackTone) -> Color {
        switch tone {
        case .success: return .green
        case .info: return .neonBlue
        case .warning: return .orange
        case .neutral: return .appSecondary
        }
    }

    // MARK: - Scan flow

    private func processScan(_ payload: String) async {
        guard case .active(let tripID, _) = tracker.state else { return }

        scanError = nil
        scanInProgress = true
        defer { scanInProgress = false }

        do {
            let outcome = try await SupabaseScanService.recordScan(
                tripID: tripID,
                qrPayload: payload,
                coordinate: nil
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                scanFeedback = ScanFeedback(outcome: outcome, timestamp: Date())
            }
            // Auto-dismiss the banner after a few seconds.
            let feedbackID = scanFeedback?.id
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if scanFeedback?.id == feedbackID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scanFeedback = nil
                    }
                }
            }
            // Refresh the log unless this was just a duplicate (no event written).
            if outcome != .duplicate {
                await refreshEventLog()
            }
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func refreshEventLog() async {
        guard case .active(let tripID, _) = tracker.state else { return }
        isLoadingLog = true
        defer { isLoadingLog = false }
        do {
            eventLog = try await SupabaseScanService.fetchEventLog(tripID: tripID)
        } catch {
            scanError = "Could not load event log: \(error.localizedDescription)"
        }
    }
}
