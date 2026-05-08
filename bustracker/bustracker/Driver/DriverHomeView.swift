import AVFoundation
import Combine
import SwiftUI

struct DriverHomeView: View {
    let profile: Profile

    @Environment(AuthViewModel.self) private var auth
    @State private var showProfileEditor = false
    @State private var tracker = TripTrackingManager()
    @State private var elapsedTickToggle = false
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

    private var firstName: String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: profile.fullName) {
            return PersonNameComponentsFormatter.localizedString(from: components, style: .short)
        }
        return profile.fullName
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
            .navigationTitle(isTripActive ? "" : "BusTracker — Driver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isTripActive ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if !isTripActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showProfileEditor = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(Color.neonBlue)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign out") {
                            Task { try? await auth.signOut() }
                        }
                        .foregroundStyle(Color.neonBlue)
                    }
                }
            }
            .sheet(isPresented: $showProfileEditor) {
                NavigationStack {
                    ProfileEditorView(mode: .edit(profile))
                }
            }
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
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                permissionCard

                if let error = tracker.lastError {
                    InlineMessage(
                        message: error,
                        color: .red,
                        icon: "exclamationmark.circle.fill"
                    )
                }

                actionButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(Color.appBg.ignoresSafeArea())
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
                statusCard

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

                if logExpanded {
                    eventLogCard.frame(maxHeight: 260)
                } else {
                    eventLogCard
                }

                actionButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hi, \(firstName)")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        }
    }

    private var headerSubtitle: String {
        switch tracker.state {
        case .idle:
            return "Start a trip when the bus is ready to leave. The app will report GPS until you end it."
        case .starting:
            return "Starting trip…"
        case .active:
            return "Trip in progress. Keep the app installed and signed in; iOS will keep reporting GPS even when the screen is off."
        case .ending:
            return "Ending trip…"
        }
    }

    @ViewBuilder
    private var permissionCard: some View {
        switch tracker.permissionStatus {
        case .always, .foregroundOnly:
            EmptyView()
        case .denied, .restricted:
            permissionWarning(
                title: "Location is disabled",
                body: "Open Settings → BusTracker → Location and pick 'While Using the App' or higher.",
                cta: "Open Settings"
            )
        case .unknown:
            permissionWarning(
                title: "Location permission needed",
                body: "BusTracker reports GPS while a trip is active so parents can see the bus. Keep the app open while driving.",
                cta: "Allow location"
            )
        }
    }

    private func permissionWarning(title: String, body: String, cta: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            Text(body)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)

            Button(cta) {
                handlePermissionTap()
            }
            .buttonStyle(NeonOutlineButtonStyle())
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

    @ViewBuilder
    private var statusCard: some View {
        if case .active(_, let startedAt) = tracker.state {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    statusExpanded.toggle()
                }
            } label: {
                VStack(spacing: 12) {
                    HStack {
                        statusBadge
                        Spacer()
                        Text(elapsedString(since: startedAt))
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        Image(systemName: statusExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.appSecondary)
                            .padding(.leading, 4)
                    }

                    if statusExpanded {
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
                elapsedTickToggle.toggle()
            }
        } else {
            EmptyView()
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

    private func elapsedString(since start: Date) -> String {
        // Read the toggle so SwiftUI re-renders this view every second.
        _ = elapsedTickToggle
        let interval = max(0, Int(Date().timeIntervalSince(start)))
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

    private var eventLogCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    logExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(Color.neonBlue)
                    Text("Trip log")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    if !eventLog.isEmpty {
                        Text("\(eventLog.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.neonBlue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.neonBlue.opacity(0.2), in: Capsule())
                    }
                    Spacer()
                    if isLoadingLog {
                        ProgressView().tint(.neonBlue).controlSize(.small)
                    }
                    Image(systemName: logExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if logExpanded {
                Divider().background(Color.appBorder)

                HStack {
                    Spacer()
                    Button {
                        Task { await refreshEventLog() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(Color.neonBlue)
                    }
                }

                if eventLog.isEmpty {
                    Text("No scans yet. Hold a student's QR in front of the camera.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(eventLog) { entry in
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
