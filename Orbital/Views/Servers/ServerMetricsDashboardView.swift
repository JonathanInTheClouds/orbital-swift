//
//  ServerMetricsDashboardView.swift
//  Orbital
//
//  Created by Codex on 4/14/26.
//

import Charts
import SwiftData
import SwiftUI

struct ServerMetricsDashboardView: View {
    let server: Server
    var openSectionOrganizer: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(MetricsPollingService.self) private var metricsPollingService
    @Query private var snapshots: [MetricSnapshot]
    @State private var showVolumeSelector = false

    init(server: Server, openSectionOrganizer: (() -> Void)? = nil) {
        self.server = server
        self.openSectionOrganizer = openSectionOrganizer

        let serverID = server.id
        _snapshots = Query(
            filter: #Predicate<MetricSnapshot> { snapshot in
                snapshot.server?.id == serverID
            },
            sort: [SortDescriptor(\MetricSnapshot.recordedAt, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if let latestSnapshot {
                VStack(spacing: 14) {
                    ForEach(visibleSections) { section in
                        metricsSectionView(section, latestSnapshot: latestSnapshot)
                    }
                }
            } else {
                emptyStatePanel
            }
        }
        .task {
            persistSectionOrderIfNeeded()
        }
        .sheet(isPresented: $showVolumeSelector) {
            NavigationStack {
                List {
                    Section {
                        Button {
                            selectAllVolumes()
                        } label: {
                            HStack {
                                Label("All Volumes", systemImage: "square.stack.3d.up")
                                Spacer()
                                if server.volumeSelectionMode == .all {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(serverAccentColor(server.colorTag))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } footer: {
                        Text("Automatically include all discovered volumes, including new ones found later.")
                    }

                    Section {
                        ForEach(availableVolumeMountPoints, id: \.self) { mountPoint in
                            Button {
                                toggleVolumeSelection(mountPoint)
                            } label: {
                                HStack {
                                    Text(mountPoint)
                                    Spacer()
                                    Image(systemName: isVolumeSelected(mountPoint) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isVolumeSelected(mountPoint) ? serverAccentColor(server.colorTag) : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Custom Selection")
                    } footer: {
                        Text("Choose exactly which volumes appear in the disk cards and primary disk gauge.")
                    }
                }
                .navigationTitle("Storage Volumes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            showVolumeSelector = false
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
                            clearVolumeSelection()
                        }
                        .disabled(server.volumeSelectionMode == .custom && server.selectedVolumeMountPoints.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var latestSnapshot: MetricSnapshot? {
        snapshots.first
    }

    private var previousSnapshot: MetricSnapshot? {
        guard snapshots.count > 1 else { return nil }
        return snapshots[1]
    }

    private var trendSamples: [MetricsTrendSample] {
        snapshots
            .prefix(18)
            .reversed()
            .map {
                MetricsTrendSample(
                    recordedAt: $0.recordedAt,
                    cpuPercent: $0.cpuPercent,
                    memoryPercent: $0.memoryUsageFraction * 100
                )
            }
    }

    private var trendPoints: [MetricsTrendPoint] {
        trendSamples.flatMap { sample in
            [
                MetricsTrendPoint(
                    recordedAt: sample.recordedAt,
                    value: sample.cpuPercent,
                    series: .cpu
                ),
                MetricsTrendPoint(
                    recordedAt: sample.recordedAt,
                    value: sample.memoryPercent,
                    series: .memory
                )
            ]
        }
    }

    private var availableDiskRows: [DiskUsage] {
        guard let latestSnapshot else { return [] }

        return latestSnapshot.diskUsages
            .filter { isSelectableVolume($0.mountPoint) }
            .sorted {
            if $0.mountPoint == "/" { return true }
            if $1.mountPoint == "/" { return false }
            return $0.usedPercent > $1.usedPercent
        }
    }

    private var availableVolumeMountPoints: [String] {
        availableDiskRows.map(\.mountPoint)
    }

    private var selectedVolumeMountPoints: Set<String> {
        switch server.volumeSelectionMode {
        case .all:
            return Set(availableVolumeMountPoints)
        case .custom:
            return Set(server.selectedVolumeMountPoints)
        }
    }

    private var diskRows: [DiskUsage] {
        availableDiskRows.filter { selectedVolumeMountPoints.contains($0.mountPoint) }
    }

    private var primaryDisplayedDiskUsage: DiskUsage? {
        diskRows.first(where: { $0.mountPoint == "/" }) ?? diskRows.first
    }

    private var latestNetworkRate: NetworkRate? {
        guard let latestSnapshot, let previousSnapshot else { return nil }
        return NetworkRate(current: latestSnapshot, previous: previousSnapshot)
    }

    private var featuredContainers: [ContainerStatusSnapshot] {
        guard let latestSnapshot else { return [] }

        return latestSnapshot.containerStatuses
            .sorted(by: containerPrioritySort)
            .prefix(5)
            .map { $0 }
    }

    private var runningContainers: [ContainerStatusSnapshot] {
        guard let latestSnapshot else { return [] }

        return latestSnapshot.containerStatuses
            .filter(\.isRunning)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var orderedSections: [MetricDashboardSection] {
        MetricDashboardSection.sanitized(from: server.metricsSectionOrder)
    }

    private var visibleSections: [MetricDashboardSection] {
        orderedSections.filter { section in
            switch section {
            case .history:
                return trendSamples.count > 1
            case .containers:
                return latestSnapshot?.hasContainerRuntime == true
            case .disks:
                return !availableDiskRows.isEmpty
            default:
                return true
            }
        }
    }

    private var gaugeColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 152), spacing: 12)]
    }

    private func overviewPanel(for snapshot: MetricSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Health Overview")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(lastUpdatedText(for: snapshot))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    statusChip(
                        title: metricsPollingService.isPolling(serverID: server.id) ? "Polling" : "Idle",
                        value: metricsPollingService.isPolling(serverID: server.id)
                        ? "\(Int(metricsPollingService.interval(for: server.id) ?? 0))s"
                        : "Manual",
                        tint: metricsPollingService.isPolling(serverID: server.id) ? .green : .gray
                    )

                    statusChip(
                        title: "SSH",
                        value: server.lastSeenAt == nil ? "Unknown" : "Healthy",
                        tint: server.lastSeenAt == nil ? .orange : .blue
                    )
                }
            }

            LazyVGrid(columns: gaugeColumns, spacing: 10) {
                MetricSummaryChip(
                    label: "Load",
                    value: String(format: "%.2f", snapshot.loadAvg1m),
                    caption: "1 minute"
                )
                MetricSummaryChip(
                    label: "Uptime",
                    value: formatDuration(snapshot.uptimeSeconds),
                    caption: "system runtime"
                )
                MetricSummaryChip(
                    label: "Inbound",
                    value: latestNetworkRate.map { formatThroughput($0.bytesInPerSecond) } ?? "Collecting",
                    caption: latestNetworkRate == nil ? "need 2 samples" : "per second"
                )
                MetricSummaryChip(
                    label: "Outbound",
                    value: latestNetworkRate.map { formatThroughput($0.bytesOutPerSecond) } ?? "Collecting",
                    caption: latestNetworkRate == nil ? "need 2 samples" : "per second"
                )
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            serverAccentColor(server.colorTag).opacity(0.22),
                            serverAccentColor(server.colorTag).opacity(0.08),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func metricsSectionView(_ section: MetricDashboardSection, latestSnapshot: MetricSnapshot) -> some View {
        switch section {
        case .overview:
            overviewPanel(for: latestSnapshot)

        case .vitals:
            vitalsPanel(for: latestSnapshot)

        case .history:
            historyPanel

        case .containers:
            containersPanel(for: latestSnapshot)

        case .system:
            systemPanel(for: latestSnapshot)

        case .disks:
            diskPanel
        }
    }

    private func vitalsPanel(for latestSnapshot: MetricSnapshot) -> some View {
        LazyVGrid(columns: gaugeColumns, spacing: 12) {
            MetricGaugeCard(
                title: "CPU",
                valueText: "\(Int(latestSnapshot.cpuPercent.rounded()))%",
                subtitle: cpuSummary(for: latestSnapshot),
                fraction: latestSnapshot.cpuPercent / 100,
                tint: .orange,
                icon: "cpu"
            )

            MetricGaugeCard(
                title: "Memory",
                valueText: formatPercent(latestSnapshot.memoryUsageFraction),
                subtitle: "\(formatBytes(latestSnapshot.memUsedBytes)) used\n\(formatBytes(latestSnapshot.memTotalBytes)) total",
                fraction: latestSnapshot.memoryUsageFraction,
                tint: .cyan,
                icon: "memorychip"
            )

            if let primaryDisk = primaryDisplayedDiskUsage {
                MetricGaugeCard(
                    title: primaryDisk.mountPoint == "/" ? "Disk" : primaryDisk.mountPoint,
                    valueText: formatPercent(primaryDisk.usedPercent),
                    subtitle: "\(formatBytes(primaryDisk.usedBytes)) used\n\(formatBytes(primaryDisk.totalBytes)) total",
                    fraction: primaryDisk.usedPercent,
                    tint: .green,
                    icon: "internaldrive"
                )
            }
        }
    }

    private var historyPanel: some View {
        MetricPanel(title: "Recent Activity", subtitle: "CPU and memory over the last \(trendSamples.count) polls") {
            VStack(alignment: .leading, spacing: 12) {
                Chart {
                    ForEach(trendSamples) { sample in
                        AreaMark(
                            x: .value("Recorded", sample.recordedAt),
                            y: .value("CPU", sample.cpuPercent)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange.opacity(0.25), .orange.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    ForEach(trendPoints.filter { $0.series == .cpu }) { point in
                        LineMark(
                            x: .value("Recorded", point.recordedAt),
                            y: .value("Percent", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(by: .value("Metric", point.series.label))
                    }

                    ForEach(trendPoints.filter { $0.series == .memory }) { point in
                        LineMark(
                            x: .value("Recorded", point.recordedAt),
                            y: .value("Percent", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                        .foregroundStyle(by: .value("Metric", point.series.label))
                    }

                    if let latestMemoryPoint = trendPoints.last(where: { $0.series == .memory }) {
                        PointMark(
                            x: .value("Recorded", latestMemoryPoint.recordedAt),
                            y: .value("Percent", latestMemoryPoint.value)
                        )
                        .symbolSize(36)
                        .foregroundStyle(.cyan)
                    }
                }
                .chartYScale(domain: 0 ... 100)
                .chartForegroundStyleScale([
                    MetricsTrendSeries.cpu.label: Color.orange,
                    MetricsTrendSeries.memory.label: Color.cyan
                ])
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 168)

                HStack(spacing: 14) {
                    legendItem(color: .orange, label: "CPU")
                    legendItem(color: .cyan, label: "Memory")
                }
            }
        }
    }

    private func containersPanel(for snapshot: MetricSnapshot) -> some View {
        MetricPanel(
            title: "Containers",
            subtitle: containerPanelSubtitle(for: snapshot)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    statusChip(
                        title: snapshot.containerRuntime.displayName,
                        value: snapshot.containerRuntimeReachable ? "Reachable" : "Unavailable",
                        tint: snapshot.containerRuntimeReachable ? .blue : .orange
                    )

                    statusChip(
                        title: "Total",
                        value: "\(snapshot.containerStatuses.count)",
                        tint: .secondary
                    )

                    Spacer(minLength: 0)

                    NavigationLink {
                        ServerContainerListView(server: server)
                    } label: {
                        Text("See More")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(serverAccentColor(server.colorTag))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(serverAccentColor(server.colorTag).opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: gaugeColumns, spacing: 10) {
                    MetricSummaryChip(
                        label: "Running",
                        value: "\(snapshot.runningContainerCount)",
                        caption: "active containers"
                    )
                    MetricSummaryChip(
                        label: "Exited",
                        value: "\(snapshot.exitedContainerCount)",
                        caption: "stopped or dead"
                    )
                    MetricSummaryChip(
                        label: "Restarting",
                        value: "\(snapshot.restartingContainerCount)",
                        caption: "recovering now"
                    )
                    MetricSummaryChip(
                        label: "Paused",
                        value: "\(snapshot.pausedContainerCount)",
                        caption: snapshot.unhealthyContainerCount > 0
                        ? "\(snapshot.unhealthyContainerCount) unhealthy"
                        : "healthy set"
                    )
                }

                if !snapshot.containerRuntimeReachable {
                    Text("\(snapshot.containerRuntime.displayName) is installed but the current session could not query it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if runningContainers.isEmpty {
                    Text(snapshot.containerStatuses.isEmpty
                         ? "No containers detected on this server."
                         : "No running containers right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(runningContainers.prefix(3), id: \.self) { container in
                            NavigationLink {
                                ServerContainerDetailView(
                                    server: server,
                                    runtime: snapshot.containerRuntime,
                                    container: container
                                )
                            } label: {
                                containerRow(container)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func systemPanel(for snapshot: MetricSnapshot) -> some View {
        MetricPanel(title: "System Detail", subtitle: "Current server health at a glance") {
            LazyVGrid(columns: gaugeColumns, spacing: 10) {
                MetricStatTile(
                    label: "Load Averages",
                    value: "\(formatLoad(snapshot.loadAvg1m)) · \(formatLoad(snapshot.loadAvg5m)) · \(formatLoad(snapshot.loadAvg15m))",
                    tone: .orange
                )

                MetricStatTile(
                    label: "Swap Usage",
                    value: snapshot.swapTotalBytes > 0
                    ? "\(formatPercent(snapshot.swapUsageFraction)) · \(formatBytes(snapshot.swapUsedBytes))"
                    : "No swap configured",
                    tone: .indigo
                )

                MetricStatTile(
                    label: "Interfaces",
                    value: snapshot.networkStats.isEmpty ? "No data" : "\(snapshot.networkStats.count) active",
                    tone: .blue
                )

                MetricStatTile(
                    label: "Recorded",
                    value: snapshot.recordedAt.formatted(date: .omitted, time: .shortened),
                    tone: .green
                )
            }
        }
    }

    private var diskPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disk Usage")
                        .font(.headline)
                    Text(diskPanelSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showVolumeSelector = true
                } label: {
                    Label("Volumes", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(serverAccentColor(server.colorTag).opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if diskRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Volumes Selected")
                        .font(.subheadline.weight(.semibold))

                    Text("Choose one or more storage volumes to show disk metrics for this server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(diskRows.prefix(4), id: \.mountPoint) { disk in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(disk.mountPoint)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(formatPercent(disk.usedPercent))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(disk.usedPercent > 0.85 ? .red : .primary)
                            }

                            ProgressView(value: min(max(disk.usedPercent, 0), 1))
                                .tint(disk.usedPercent > 0.85 ? .red : .green)

                            HStack {
                                Text("\(formatBytes(disk.usedBytes)) used")
                                Spacer()
                                Text("\(formatBytes(disk.totalBytes)) total")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        }
                    }
                }
            }
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

    private var emptyStatePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("No Metrics Yet")
                    .font(.title3.weight(.semibold))

                if let openSectionOrganizer {
                    Button {
                        openSectionOrganizer()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(serverAccentColor(server.colorTag))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Organize server sections")
                }
            }

            Text("Start polling or run a manual sample to populate the dashboard for this server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func statusChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func containerRow(_ container: ContainerStatusSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(containerTint(for: container))
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(container.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(containerStatusLabel(for: container))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(containerTint(for: container))
                }

                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(container.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        }
    }

    private func lastUpdatedText(for snapshot: MetricSnapshot) -> String {
        "Updated \(snapshot.recordedAt.formatted(.relative(presentation: .named)))"
    }

    private func cpuSummary(for snapshot: MetricSnapshot) -> String {
        "Load \(formatLoad(snapshot.loadAvg1m))"
    }

    private func formatPercent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private func formatLoad(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatBytes(_ value: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: value)
    }

    private func formatDuration(_ seconds: Int64) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatThroughput(_ bytesPerSecond: Double) -> String {
        let intValue = Int64(bytesPerSecond.rounded())
        return "\(Self.byteFormatter.string(fromByteCount: intValue))/s"
    }

    private func containerPanelSubtitle(for snapshot: MetricSnapshot) -> String {
        if !snapshot.containerRuntimeReachable {
            return "\(snapshot.containerRuntime.displayName) detected but unavailable to the current user"
        }

        return snapshot.containerStatuses.isEmpty
        ? "\(snapshot.containerRuntime.displayName) is available, but no containers were found"
        : "\(runningContainers.count) running of \(snapshot.containerStatuses.count) total \(snapshot.containerRuntime.displayName.lowercased()) containers"
    }

    private func containerPrioritySort(_ lhs: ContainerStatusSnapshot, _ rhs: ContainerStatusSnapshot) -> Bool {
        let lhsPriority = containerPriority(for: lhs)
        let rhsPriority = containerPriority(for: rhs)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func containerPriority(for container: ContainerStatusSnapshot) -> Int {
        if container.isUnhealthy { return 0 }
        if container.isRestarting { return 1 }
        if container.isExited { return 2 }
        if container.isPaused { return 3 }
        if container.isRunning { return 4 }
        return 5
    }

    private func containerTint(for container: ContainerStatusSnapshot) -> Color {
        if container.isUnhealthy { return .red }
        if container.isRestarting { return .orange }
        if container.isExited { return .secondary }
        if container.isPaused { return .yellow }
        if container.isRunning { return .green }
        return .blue
    }

    private func containerStatusLabel(for container: ContainerStatusSnapshot) -> String {
        if let healthLabel = container.healthLabel {
            return healthLabel
        }
        return container.state.capitalized
    }

    private var diskPanelSubtitle: String {
        if availableDiskRows.isEmpty {
            return "No storage volumes discovered yet"
        }

        switch server.volumeSelectionMode {
        case .all:
            return "Showing all \(availableDiskRows.count) discovered volumes"
        case .custom:
            return diskRows.isEmpty
            ? "No volumes selected"
            : "Showing \(diskRows.count) of \(availableDiskRows.count) selected volumes"
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private func persistSectionOrderIfNeeded() {
        let normalizedOrder = orderedSections.map(\.rawValue)
        guard server.metricsSectionOrder != normalizedOrder else { return }
        server.metricsSectionOrder = normalizedOrder
        saveServerChanges()
    }

    private func saveServerChanges() {
        try? modelContext.save()
    }

    private func selectAllVolumes() {
        server.volumeSelectionMode = .all
        saveServerChanges()
    }

    private func clearVolumeSelection() {
        server.volumeSelectionMode = .custom
        server.selectedVolumeMountPoints = []
        saveServerChanges()
    }

    private func toggleVolumeSelection(_ mountPoint: String) {
        var updated = Set(server.volumeSelectionMode == .all ? availableVolumeMountPoints : server.selectedVolumeMountPoints)

        if updated.contains(mountPoint) {
            updated.remove(mountPoint)
        } else {
            updated.insert(mountPoint)
        }

        server.volumeSelectionMode = .custom
        server.selectedVolumeMountPoints = availableVolumeMountPoints.filter { updated.contains($0) }
        saveServerChanges()
    }

    private func isVolumeSelected(_ mountPoint: String) -> Bool {
        selectedVolumeMountPoints.contains(mountPoint)
    }

    private func isSelectableVolume(_ mountPoint: String) -> Bool {
        switch mountPoint {
        case "/run", "/tmp", "/dev", "/proc", "/sys":
            return false
        default:
            break
        }

        let excludedPrefixes = ["/run/", "/dev/", "/proc/", "/sys/"]
        return !excludedPrefixes.contains { mountPoint.hasPrefix($0) }
    }
}

enum MetricDashboardSection: String, CaseIterable, Identifiable {
    case overview
    case vitals
    case history
    case containers
    case system
    case disks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .vitals:
            return "Vitals"
        case .history:
            return "History"
        case .containers:
            return "Containers"
        case .system:
            return "System Detail"
        case .disks:
            return "Disks"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return "Top summary and connection health"
        case .vitals:
            return "CPU, memory, and primary disk gauges"
        case .history:
            return "Recent CPU and memory trend lines"
        case .containers:
            return "Docker or Podman runtime and container health"
        case .system:
            return "Load, swap, interfaces, and timestamp"
        case .disks:
            return "Filesystem pressure details"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "rectangle.grid.2x2"
        case .vitals:
            return "gauge.with.dots.needle.33percent"
        case .history:
            return "chart.line.uptrend.xyaxis"
        case .containers:
            return "shippingbox"
        case .system:
            return "cpu"
        case .disks:
            return "internaldrive"
        }
    }

    static var defaultOrder: [MetricDashboardSection] {
        [.overview, .vitals, .history, .containers, .system, .disks]
    }

    static func sanitized(from rawValues: [String]) -> [MetricDashboardSection] {
        let requested = rawValues.compactMap(Self.init(rawValue:))
        var seen: Set<MetricDashboardSection> = []
        var ordered = requested.filter { seen.insert($0).inserted }

        for section in allCases where !seen.contains(section) {
            ordered.append(section)
        }

        return ordered
    }
}

private struct MetricsTrendSample: Identifiable {
    let recordedAt: Date
    let cpuPercent: Double
    let memoryPercent: Double

    var id: Date { recordedAt }
}

private struct MetricsTrendPoint: Identifiable {
    let recordedAt: Date
    let value: Double
    let series: MetricsTrendSeries

    var id: String {
        "\(series.rawValue)-\(recordedAt.timeIntervalSinceReferenceDate)"
    }
}

private enum MetricsTrendSeries: String {
    case cpu
    case memory

    var label: String {
        switch self {
        case .cpu:
            return "CPU"
        case .memory:
            return "Memory"
        }
    }
}

private struct NetworkRate {
    let bytesInPerSecond: Double
    let bytesOutPerSecond: Double

    init?(current: MetricSnapshot, previous: MetricSnapshot) {
        let interval = current.recordedAt.timeIntervalSince(previous.recordedAt)
        guard interval > 0 else { return nil }

        let previousMap = Dictionary(uniqueKeysWithValues: previous.networkStats.map { ($0.interface, $0) })
        var inboundDelta: Int64 = 0
        var outboundDelta: Int64 = 0

        for stat in current.networkStats where stat.interface != "lo" {
            guard let older = previousMap[stat.interface] else { continue }
            inboundDelta += max(stat.bytesIn - older.bytesIn, 0)
            outboundDelta += max(stat.bytesOut - older.bytesOut, 0)
        }

        self.bytesInPerSecond = Double(inboundDelta) / interval
        self.bytesOutPerSecond = Double(outboundDelta) / interval
    }
}

private struct MetricPanel<Content: View>: View {
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

private struct MetricGaugeCard: View {
    private static let subtitleHeight: CGFloat = 32

    let title: String
    let valueText: String
    let subtitle: String
    let fraction: Double
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            MetricRing(fraction: fraction, tint: tint) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(valueText)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: Self.subtitleHeight, maxHeight: Self.subtitleHeight, alignment: .topLeading)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(tint.opacity(0.15), lineWidth: 1)
                }
        }
    }
}

private struct MetricRing<Content: View>: View {
    let fraction: Double
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: 10)

            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.35), tint, tint.opacity(0.75)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            content
        }
        .frame(width: 56, height: 56)
    }
}

private struct MetricSummaryChip: View {
    let label: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }
}

private struct MetricStatTile: View {
    let label: String
    let value: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tone.opacity(0.10))
        }
    }
}
