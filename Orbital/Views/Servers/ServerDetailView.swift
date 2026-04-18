//
//  ServerDetailView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftData
import SwiftUI

struct ServerDetailView: View {
    let server: Server

    @Environment(\.modelContext) private var modelContext
    @Environment(SSHService.self) private var sshService
    @Environment(MetricsPollingService.self) private var metricsPollingService
    @State private var showEditServer = false
    @State private var showSectionOrganizer = false
    @State private var connectError: IdentifiableError?
    @State private var launchedSession: SSHSession?
    @State private var pollingInterval: Double = 30

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                ForEach(visibleSections) { section in
                    sectionView(for: section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .refreshable {
            await pollNow()
        }
        .task {
            persistSectionOrderIfNeeded()
        }
        .background(backgroundGradient)
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showSectionOrganizer = true
                } label: {
                    Label("Organize", systemImage: "arrow.up.arrow.down.circle")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditServer = true }
            }
        }
        .sheet(isPresented: $showEditServer) {
            AddEditServerView(server: server)
        }
        .sheet(isPresented: $showSectionOrganizer) {
            NavigationStack {
                List {
                    Section("Page Sections") {
                        ForEach(orderedSections) { section in
                            HStack(spacing: 12) {
                                Image(systemName: section.systemImage)
                                    .foregroundStyle(accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.title)
                                    Text(section.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onMove(perform: moveDetailSections)
                    }

                    Section("Metrics Panels") {
                        ForEach(orderedMetricSections) { section in
                            HStack(spacing: 12) {
                                Image(systemName: section.systemImage)
                                    .foregroundStyle(accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.title)
                                    Text(section.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onMove(perform: moveMetricSections)
                    }
                }
                .navigationTitle("Organize Server")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            showSectionOrganizer = false
                        }
                    }

                    ToolbarItem(placement: .secondaryAction) {
                        Button("Reset") {
                            resetSectionOrder()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(isPresented: Binding(
            get: { launchedSession != nil },
            set: { if !$0 { launchedSession = nil } }
        )) {
            if let session = launchedSession {
                TerminalView(session: session)
            }
        }
        .alert("Connection Error", isPresented: Binding(
            get: { connectError != nil },
            set: { if !$0 { connectError = nil } }
        )) {
            Button("OK") { connectError = nil }
        } message: {
            Text(connectError?.message ?? "")
        }
    }

    private var currentStatus: ConnectionStatus {
        sshService.status(for: server.id)
    }

    private var activeSessionCount: Int {
        sshService.activeSessionCount(for: server.id)
    }

    private var hasActiveSession: Bool {
        activeSessionCount > 0
    }

    private var displayStatus: ConnectionStatus {
        serverDisplayStatus(
            sessionStatus: currentStatus,
            lastReachableAt: [
                server.lastSeenAt,
                metricsPollingService.lastRecordedAt(for: server.id),
                sshService.lastReachableAt(for: server.id)
            ]
            .compactMap { $0 }
            .max()
        )
    }

    private var orderedSections: [ServerDetailSection] {
        ServerDetailSection.sanitized(from: server.detailSectionOrder)
    }

    private var orderedMetricSections: [MetricDashboardSection] {
        MetricDashboardSection.sanitized(from: server.metricsSectionOrder)
    }

    private var visibleSections: [ServerDetailSection] {
        orderedSections.filter { section in
            switch section {
            case .details:
                return !server.tags.isEmpty || !server.notes.isEmpty
            default:
                return true
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 60, height: 60)
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(server.name)
                        .font(.title2.weight(.bold))

                    Text("\(server.username)@\(server.host):\(server.port)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if server.osKind != .unknown {
                        Label(server.osKind.displayName, systemImage: server.osKind.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let lastSeen = server.lastSeenAt {
                        Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                StatusBadge(status: displayStatus)
            }

            if !server.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(server.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.06), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.20),
                            accentColor.opacity(0.08),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                }
        }
    }

    private var accentColor: Color {
        serverAccentColor(server.colorTag)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                accentColor.opacity(0.10),
                Color(uiColor: .systemBackground),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var isPolling: Bool {
        metricsPollingService.isPolling(serverID: server.id)
    }

    private var lastRecordedAt: Date? {
        metricsPollingService.lastRecordedAt(for: server.id)
    }

    private var lastError: String? {
        metricsPollingService.lastError(for: server.id)
    }

    private var isDynamicIslandEnabled: Bool {
        metricsPollingService.isDynamicIslandEnabled(for: server.id)
    }

    @ViewBuilder
    private func sectionView(for section: ServerDetailSection) -> some View {
        switch section {
        case .metrics:
            ServerMetricsDashboardView(
                server: server,
                openSectionOrganizer: { showSectionOrganizer = true }
            )

        case .connection:
            DetailCardSection(title: "Connection", subtitle: "Transport and authentication settings") {
                VStack(spacing: 14) {
                    LabeledRow(label: "Host", value: server.host)
                    LabeledRow(label: "Port", value: "\(server.port)")
                    LabeledRow(label: "Username", value: server.username)
                    LabeledRow(label: "Auth", value: server.authMethod.displayName)

                    if let jumpHost = server.jumpHostRef, !jumpHost.isEmpty {
                        LabeledRow(label: "Jump Host", value: jumpHost)
                    }
                }
            }

        case .details:
            DetailCardSection(title: "Details", subtitle: "Metadata and notes for this node") {
                VStack(alignment: .leading, spacing: 14) {
                    if !server.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            FlowLayout(spacing: 6) {
                                ForEach(server.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(accentColor.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }

                    if !server.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(server.notes)
                                .font(.subheadline)
                        }
                    }
                }
            }

        case .monitoring:
            DetailCardSection(title: "Monitoring", subtitle: "Polling cadence and collection health") {
                VStack(spacing: 14) {
                    VStack(spacing: 12) {
                        LabeledRow(label: "Polling", value: isPolling ? "Active" : "Stopped")
                        LabeledRow(label: "Interval", value: "\(Int(pollingInterval))s")
                        LabeledRow(label: "Dynamic Island", value: isDynamicIslandEnabled ? "Enabled" : "Off")

                        if let lastRecordedAt {
                            LabeledRow(
                                label: "Last Snapshot",
                                value: lastRecordedAt.formatted(date: .abbreviated, time: .standard)
                            )
                        }

                        if let lastError {
                            LabeledRow(label: "Last Error", value: lastError)
                                .foregroundStyle(.red)
                        }
                    }

                    Stepper(value: $pollingInterval, in: 5 ... 300, step: 5) {
                        Text("Poll Every \(Int(pollingInterval)) Seconds")
                            .font(.subheadline.weight(.medium))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dynamic Island appears for one monitored server at a time and ends when monitoring stops or the feed goes stale.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            metricsPollingService.setDynamicIslandEnabled(!isDynamicIslandEnabled, for: server)
                        } label: {
                            Label(
                                isDynamicIslandEnabled ? "Disable Dynamic Island" : "Show in Dynamic Island",
                                systemImage: isDynamicIslandEnabled ? "iphone.gen3.slash" : "iphone.gen3.radiowaves.left.and.right"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isPolling)
                    }

                    VStack(spacing: 10) {
                        Button {
                            metricsPollingService.startPolling(server: server, every: pollingInterval)
                        } label: {
                            Label(
                                isPolling ? "Restart Polling" : "Start Polling",
                                systemImage: "waveform.path.ecg"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        HStack(spacing: 10) {
                            Button {
                                Task { await pollNow() }
                            } label: {
                                Label("Poll Now", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            if isPolling {
                                Button(role: .destructive) {
                                    metricsPollingService.stopPolling(serverID: server.id)
                                } label: {
                                    Label("Stop", systemImage: "stop.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

        case .actions:
            DetailCardSection(title: "Actions", subtitle: "Interactive shell and session control") {
                VStack(spacing: 10) {
                    Button {
                        Task { await connectAndOpenTerminal() }
                    } label: {
                        Label(
                            hasActiveSession ? "Open New Terminal" : "Connect & Open Terminal",
                            systemImage: "terminal"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasActiveSession && currentStatus == .connecting)

                    if hasActiveSession {
                        Button(role: .destructive) {
                            sshService.disconnect(serverID: server.id)
                        } label: {
                            Label(activeSessionCount > 1 ? "Disconnect All Sessions" : "Disconnect", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func connectAndOpenTerminal() async {
        do {
            launchedSession = try await sshService.createSession(to: server)
        } catch {
            connectError = IdentifiableError(message: error.localizedDescription)
        }
    }

    private func pollNow() async {
        do {
            try await metricsPollingService.pollNow(server: server)
        } catch {
            connectError = IdentifiableError(message: error.localizedDescription)
        }
    }

    private func moveDetailSections(from source: IndexSet, to destination: Int) {
        var updatedOrder = orderedSections
        updatedOrder.move(fromOffsets: source, toOffset: destination)
        server.detailSectionOrder = updatedOrder.map(\.rawValue)
        saveServerChanges()
    }

    private func moveMetricSections(from source: IndexSet, to destination: Int) {
        var updatedOrder = orderedMetricSections
        updatedOrder.move(fromOffsets: source, toOffset: destination)
        server.metricsSectionOrder = updatedOrder.map(\.rawValue)
        saveServerChanges()
    }

    private func persistSectionOrderIfNeeded() {
        let normalizedOrder = orderedSections.map(\.rawValue)
        let normalizedMetricOrder = orderedMetricSections.map(\.rawValue)
        guard server.detailSectionOrder != normalizedOrder || server.metricsSectionOrder != normalizedMetricOrder else { return }
        server.detailSectionOrder = normalizedOrder
        server.metricsSectionOrder = normalizedMetricOrder
        saveServerChanges()
    }

    private func resetSectionOrder() {
        server.detailSectionOrder = ServerDetailSection.defaultOrder.map(\.rawValue)
        server.metricsSectionOrder = MetricDashboardSection.defaultOrder.map(\.rawValue)
        saveServerChanges()
    }

    private func saveServerChanges() {
        do {
            try modelContext.save()
        } catch {
            connectError = IdentifiableError(message: "Failed to save server changes: \(error.localizedDescription)")
        }
    }
}

private enum ServerDetailSection: String, CaseIterable, Identifiable {
    case metrics
    case connection
    case details
    case monitoring
    case actions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metrics:
            return "Metrics"
        case .connection:
            return "Connection"
        case .details:
            return "Details"
        case .monitoring:
            return "Monitoring"
        case .actions:
            return "Actions"
        }
    }

    var subtitle: String {
        switch self {
        case .metrics:
            return "Health dashboard and recent trends"
        case .connection:
            return "Host, auth, and jump settings"
        case .details:
            return "Tags and notes"
        case .monitoring:
            return "Polling cadence and manual controls"
        case .actions:
            return "Shell access and disconnect controls"
        }
    }

    var systemImage: String {
        switch self {
        case .metrics:
            return "waveform.path.ecg.rectangle"
        case .connection:
            return "network"
        case .details:
            return "tag"
        case .monitoring:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .actions:
            return "slider.horizontal.3"
        }
    }

    static var defaultOrder: [ServerDetailSection] {
        [.metrics, .connection, .details, .monitoring, .actions]
    }

    static func sanitized(from rawValues: [String]) -> [ServerDetailSection] {
        let requested = rawValues.compactMap(Self.init(rawValue:))
        var seen: Set<ServerDetailSection> = []
        var ordered = requested.filter { seen.insert($0).inserted }

        for section in allCases where !seen.contains(section) {
            ordered.append(section)
        }

        return ordered
    }
}

struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct DetailCardSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, in: proposal.width ?? 0).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, in: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct LayoutResult {
        var frames: [CGRect]
        var size: CGSize
    }

    private func layout(subviews: Subviews, in width: CGFloat) -> LayoutResult {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return LayoutResult(
            frames: frames,
            size: CGSize(width: width, height: y + rowHeight)
        )
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Server.self,
        MetricSnapshot.self,
        Script.self,
        ScriptRun.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let server = Server(
        name: "prod-web-01",
        host: "192.168.1.100",
        port: 22,
        username: "admin",
        tags: ["production", "web", "edge"],
        notes: "Primary web server in us-east-1.",
        colorTag: "teal"
    )
    context.insert(server)

    let now = Date()
    for offset in stride(from: 70, through: 0, by: -10) {
        let recordedAt = now.addingTimeInterval(TimeInterval(-offset * 60))
        let cpu = Double(35 + (offset % 25))
        let memoryUsed = Int64(3_600_000_000 + (offset * 18_000_000))
        let rx = Int64(2_000_000_000 + offset * 55_000_000)
        let tx = Int64(1_200_000_000 + offset * 32_000_000)

        context.insert(
            MetricSnapshot(
                server: server,
                recordedAt: recordedAt,
                cpuPercent: cpu,
                memUsedBytes: memoryUsed,
                memTotalBytes: 8_589_934_592,
                swapUsedBytes: 512_000_000,
                swapTotalBytes: 2_147_483_648,
                diskUsages: [
                    DiskUsage(mountPoint: "/", usedBytes: 45_000_000_000, totalBytes: 85_000_000_000),
                    DiskUsage(mountPoint: "/data", usedBytes: 120_000_000_000, totalBytes: 200_000_000_000)
                ],
                networkStats: [
                    NetworkStat(interface: "eth0", bytesIn: rx, bytesOut: tx)
                ],
                containerRuntime: .docker,
                containerRuntimeReachable: true,
                containerStatuses: [
                    ContainerStatusSnapshot(name: "web", image: "nginx:latest", state: "running", status: "Up 3 hours (healthy)"),
                    ContainerStatusSnapshot(name: "worker", image: "ghcr.io/acme/worker:1.4", state: "running", status: "Up 3 hours"),
                    ContainerStatusSnapshot(name: "postgres", image: "postgres:16", state: "exited", status: "Exited (1) 12 minutes ago")
                ],
                loadAvg1m: 0.82,
                loadAvg5m: 0.74,
                loadAvg15m: 0.61,
                uptimeSeconds: 492_000
            )
        )
    }

    return NavigationStack {
        ServerDetailView(server: server)
    }
    .modelContainer(container)
    .environment(SSHService.shared)
    .environment(
        MetricsPollingService(
            modelContext: container.mainContext,
            sshService: .shared,
            liveActivityCoordinator: ServerHealthLiveActivityCoordinator()
        )
    )
}
