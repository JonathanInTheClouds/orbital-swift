//
//  ContainersView.swift
//  Orbital
//
//  Created by Jonathan on 4/14/26.
//

import SwiftUI
import SwiftData

// MARK: - Layout Style

enum ContainersLayoutStyle: String {
    case serverCards
    case containerList
}

// MARK: - Container Entry (used by classic layout)

struct ContainerEntry: Identifiable {
    var id: String { "\(serverID.uuidString)_\(container.name)" }
    let server: Server
    let serverID: UUID
    let runtime: ContainerRuntimeKind
    let container: ContainerStatusSnapshot
    let snapshotDate: Date
}

// MARK: - View

struct ContainersView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(MetricsPollingService.self) private var metricsPollingService

    @Query(sort: \Server.name) private var servers: [Server]
    @Query(sort: \MetricSnapshot.recordedAt, order: .reverse) private var snapshots: [MetricSnapshot]

    @AppStorage("containersLayoutStyle") private var layoutStyle: ContainersLayoutStyle = .serverCards
    @AppStorage("containerCardStyleByEntryID") private var cardStyleStorage = ""
    @AppStorage("serverContainerCardStyleByServerID") private var serverCardStyleStorage = ""

    @State private var searchText = ""
    @State private var selectedFilter: ContainerListFilter = .all
    @State private var actionError: IdentifiableError?

    var body: some View {
        NavigationStack {
            Group {
                switch layoutStyle {
                case .serverCards:
                    serverCardsContent
                case .containerList:
                    classicContent
                }
            }
            .background(listBackground)
            .navigationTitle("Containers")
            .searchable(
                text: $searchText,
                prompt: layoutStyle == .serverCards ? "Search servers" : "Search containers"
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            layoutStyle = layoutStyle == .serverCards ? .containerList : .serverCards
                        }
                    } label: {
                        Image(systemName: layoutStyle == .serverCards ? "list.bullet" : "square.grid.2x2")
                    }
                    .accessibilityLabel(layoutStyle == .serverCards ? "Switch to list layout" : "Switch to card layout")
                }

                if layoutStyle == .containerList {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Status", selection: $selectedFilter) {
                                ForEach(ContainerListFilter.allCases) { filter in
                                    Label(filter.title, systemImage: filter.systemImage)
                                        .tag(filter)
                                }
                            }
                        } label: {
                            Image(systemName: selectedFilter == .all
                                  ? "line.3.horizontal.decrease.circle"
                                  : "line.3.horizontal.decrease.circle.fill")
                        }
                        .accessibilityLabel("Filter containers")
                    }
                }
            }
            .alert(
                "Container Action Failed",
                isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
            ) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError?.message ?? "")
            }
        }
    }

    // MARK: - Server Cards Layout

    @ViewBuilder
    private var serverCardsContent: some View {
        if serversWithSnapshots.isEmpty {
            emptyState
        } else if filteredServers.isEmpty {
            searchEmptyState
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(filteredServers) { server in
                        if let snapshot = latestSnapshotByServerID[server.id] {
                            ServerContainerCard(
                                server: server,
                                snapshot: snapshot,
                                style: serverCardStyle(for: server.id),
                                onToggleStyle: { toggleServerCardStyle(for: server.id) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Classic List Layout

    @ViewBuilder
    private var classicContent: some View {
        if allEntries.isEmpty {
            emptyState
        } else if filteredEntries.isEmpty {
            filteredEmptyState
        } else {
            List {
                ForEach(groupedEntries, id: \.server.id) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            NavigationLink {
                                ContainerDetailView(
                                    server: entry.server,
                                    runtime: entry.runtime,
                                    containerName: entry.container.name,
                                    initialContainer: entry.container
                                )
                            } label: {
                                ContainerCardView(
                                    container: entry.container,
                                    serverName: entry.server.name,
                                    runtime: entry.runtime,
                                    style: containerCardStyle(for: entry.id)
                                )
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    toggleContainerCardStyle(for: entry.id)
                                } label: {
                                    Label(
                                        containerCardStyle(for: entry.id) == .expanded ? "Condense" : "Detail",
                                        systemImage: containerCardStyle(for: entry.id) == .expanded
                                            ? "rectangle.compress.vertical"
                                            : "rectangle.grid.1x2"
                                    )
                                }
                                .tint(.indigo)

                                if entry.container.isRunning || entry.container.isPaused || entry.container.isRestarting {
                                    Button(role: .destructive) {
                                        Task { await performAction(.stop, on: entry) }
                                    } label: {
                                        Label("Stop", systemImage: "stop.fill")
                                    }
                                } else {
                                    Button {
                                        Task { await performAction(.start, on: entry) }
                                    } label: {
                                        Label("Start", systemImage: "play.fill")
                                    }
                                    .tint(.green)
                                }
                            }
                            .contextMenu {
                                Button {
                                    toggleContainerCardStyle(for: entry.id)
                                } label: {
                                    Label(
                                        containerCardStyle(for: entry.id) == .expanded ? "Show Condensed Card" : "Show Detailed Card",
                                        systemImage: containerCardStyle(for: entry.id) == .expanded
                                            ? "rectangle.compress.vertical"
                                            : "rectangle.grid.1x2"
                                    )
                                }

                                Divider()

                                Button {
                                    Task { await performAction(.start, on: entry) }
                                } label: {
                                    Label("Start", systemImage: "play.fill")
                                }

                                Button {
                                    Task { await performAction(.stop, on: entry) }
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                }

                                Button {
                                    Task { await performAction(.restart, on: entry) }
                                } label: {
                                    Label("Restart", systemImage: "arrow.clockwise")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    Task { await performAction(.remove, on: entry) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        classicSectionHeader(server: group.server, runtime: group.entries.first?.runtime ?? .none)
                    }
                }
            }
            .listStyle(.plain)
            .animation(.default, value: groupedEntries.flatMap(\.entries).map(\.id))
        }
    }

    private func classicSectionHeader(server: Server, runtime: ContainerRuntimeKind) -> some View {
        HStack(spacing: 8) {
            Text(server.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            if runtime != .none {
                Text(runtime.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .textCase(nil)
    }

    // MARK: - Empty States

    private var emptyState: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.cyan.opacity(0.14))
                            .frame(width: 88, height: 88)

                        Image(systemName: "shippingbox")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }

                    VStack(spacing: 8) {
                        Text("No Containers")
                            .font(.title2.weight(.bold))

                        Text(servers.isEmpty
                             ? "Add a server first, then run a metrics poll to see containers."
                             : "Servers with Docker or Podman will show their containers here after a metrics poll.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        if servers.isEmpty {
                            Text("Use the Servers tab to add your first host.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Metrics are collected automatically while polling is active.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 8) {
                            containerEmptyStatePill("Docker", tint: .cyan)
                            containerEmptyStatePill("Podman", tint: .teal)
                            containerEmptyStatePill("Live Status", tint: .indigo)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: 460)
                .background {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.18),
                                    Color.cyan.opacity(0.05),
                                    Color(uiColor: .secondarySystemBackground)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, proxy.size.height * 0.12)
                .padding(.bottom, 32)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
    }

    private var searchEmptyState: some View {
        ContentUnavailableView {
            Label("No Matching Servers", systemImage: "magnifyingglass")
        } description: {
            Text("No servers match \"\(searchText)\".")
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label(
                "No Matching Containers",
                systemImage: selectedFilter == .all ? "magnifyingglass" : "line.3.horizontal.decrease.circle"
            )
        } description: {
            if searchText.isEmpty {
                Text("No containers match the \(selectedFilter.title.lowercased()) filter.")
            } else {
                Text("No containers match \"\(searchText)\" with the \(selectedFilter.title.lowercased()) filter.")
            }
        } actions: {
            if selectedFilter != .all {
                Button("Show All Containers") { selectedFilter = .all }
            }
        }
    }

    // MARK: - Background

    private var listBackground: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                .cyan.opacity(0.06),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Shared Data

    private var latestSnapshotByServerID: [UUID: MetricSnapshot] {
        var result: [UUID: MetricSnapshot] = [:]
        for snapshot in snapshots {
            guard let serverID = snapshot.serverID, result[serverID] == nil else { continue }
            result[serverID] = snapshot
        }
        return result
    }

    // MARK: - Server Cards Data

    private var serversWithSnapshots: [Server] {
        servers.filter { latestSnapshotByServerID[$0.id] != nil }
    }

    private var filteredServers: [Server] {
        guard !searchText.isEmpty else { return serversWithSnapshots }
        let q = searchText.lowercased()
        return serversWithSnapshots.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: - Classic Layout Data

    private var allEntries: [ContainerEntry] {
        servers.flatMap { server -> [ContainerEntry] in
            guard
                let snapshot = latestSnapshotByServerID[server.id],
                snapshot.containerRuntimeReachable
            else { return [] }

            return snapshot.containerStatuses.map { container in
                ContainerEntry(
                    server: server,
                    serverID: server.id,
                    runtime: snapshot.containerRuntime,
                    container: container,
                    snapshotDate: snapshot.recordedAt
                )
            }
        }
    }

    private func entryPriority(_ entry: ContainerEntry) -> Int {
        if entry.container.isUnhealthy  { return 0 }
        if entry.container.isRestarting { return 1 }
        if entry.container.isRunning    { return 2 }
        if entry.container.isPaused     { return 3 }
        if entry.container.isExited     { return 4 }
        return 5
    }

    private var sortedEntries: [ContainerEntry] {
        allEntries.sorted { lhs, rhs in
            let lp = entryPriority(lhs), rp = entryPriority(rhs)
            if lp != rp { return lp < rp }
            if lhs.server.name != rhs.server.name {
                return lhs.server.name.localizedCaseInsensitiveCompare(rhs.server.name) == .orderedAscending
            }
            return lhs.container.name.localizedCaseInsensitiveCompare(rhs.container.name) == .orderedAscending
        }
    }

    private var filteredEntries: [ContainerEntry] {
        sortedEntries.filter { entry in
            guard entry.container.matches(selectedFilter) else { return false }
            guard !searchText.isEmpty else { return true }

            let q = searchText.lowercased()
            return entry.container.name.lowercased().contains(q) ||
                entry.container.image.lowercased().contains(q) ||
                entry.server.name.lowercased().contains(q)
        }
    }

    private var groupedEntries: [(server: Server, entries: [ContainerEntry])] {
        let byServer = Dictionary(grouping: filteredEntries, by: \.serverID)
        return servers
            .filter { byServer[$0.id] != nil }
            .map { server in (server: server, entries: byServer[server.id]!) }
    }

    // MARK: - Server Card Style

    private var serverCardStylesByID: [String: String] {
        CardStylePreferenceStore.read(from: serverCardStyleStorage)
    }

    private func serverCardStyle(for serverID: UUID) -> ServerContainerCardStyle {
        guard let raw = serverCardStylesByID[serverID.uuidString],
              let style = ServerContainerCardStyle(rawValue: raw) else { return .expanded }
        return style
    }

    private func toggleServerCardStyle(for serverID: UUID) {
        let next: ServerContainerCardStyle = serverCardStyle(for: serverID) == .expanded ? .condensed : .expanded
        var styles = serverCardStylesByID
        styles[serverID.uuidString] = next.rawValue
        serverCardStyleStorage = CardStylePreferenceStore.write(styles)
    }

    // MARK: - Container Card Style (classic layout)

    private var containerCardStylesByID: [String: String] {
        CardStylePreferenceStore.read(from: cardStyleStorage)
    }

    private func containerCardStyle(for entryID: String) -> ContainerCardStyle {
        guard let raw = containerCardStylesByID[entryID],
              let style = ContainerCardStyle(rawValue: raw) else { return .compact }
        return style
    }

    private func toggleContainerCardStyle(for entryID: String) {
        let next: ContainerCardStyle = containerCardStyle(for: entryID) == .expanded ? .compact : .expanded
        var styles = containerCardStylesByID
        styles[entryID] = next.rawValue
        cardStyleStorage = CardStylePreferenceStore.write(styles)
    }

    // MARK: - Actions (classic layout)

    private func performAction(_ action: ContainerAction, on entry: ContainerEntry) async {
        guard entry.runtime != .none else { return }
        do {
            let result = try await sshService.runCommand(
                action.command(for: entry.container.name, runtime: entry.runtime),
                on: entry.server
            )
            guard result.exitStatus == 0 else {
                let msg = result.standardErrorString.trimmingCharacters(in: .whitespacesAndNewlines)
                actionError = IdentifiableError(
                    message: msg.isEmpty ? "\(action.title) failed with status \(result.exitStatus)." : msg
                )
                return
            }
            try? await metricsPollingService.pollNow(server: entry.server)
        } catch {
            actionError = IdentifiableError(message: error.localizedDescription)
        }
    }
}

// MARK: - Server Container Card

enum ServerContainerCardStyle: String {
    case expanded
    case condensed
}

private struct ServerContainerCard: View {
    let server: Server
    let snapshot: MetricSnapshot
    var style: ServerContainerCardStyle = .expanded
    var onToggleStyle: (() -> Void)? = nil

    private var accentColor: Color {
        serverAccentColor(server.colorTag)
    }

    private var previewContainers: [ContainerStatusSnapshot] {
        snapshot.containerStatuses
            .filter { $0.isUnhealthy || $0.isRestarting || $0.isRunning || $0.isPaused }
            .sorted { containerPreviewPriority($0) < containerPreviewPriority($1) }
            .prefix(3)
            .map { $0 }
    }

    private func containerPreviewPriority(_ c: ContainerStatusSnapshot) -> Int {
        if c.isUnhealthy   { return 0 }
        if c.isRestarting  { return 1 }
        if c.isRunning     { return 2 }
        if c.isPaused      { return 3 }
        return 4
    }

    var body: some View {
        Group {
            switch style {
            case .expanded:
                expandedCard
            case .condensed:
                condensedCard
            }
        }
        .contextMenu {
            Button {
                onToggleStyle?()
            } label: {
                Label(
                    style == .expanded ? "Condense Card" : "Expand Card",
                    systemImage: style == .expanded
                        ? "rectangle.compress.vertical"
                        : "rectangle.grid.1x2"
                )
            }

            NavigationLink {
                ServerContainerListView(server: server)
            } label: {
                Label("See All Containers", systemImage: "shippingbox")
            }
        }
    }

    // MARK: - Expanded

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            Divider().padding(.horizontal, 16)

            statsSection

            if !previewContainers.isEmpty {
                Divider().padding(.horizontal, 16)
                containersPreviewSection
            }

            Divider().padding(.horizontal, 16)

            seeAllButton
        }
        .cardBackground(accentColor: accentColor)
    }

    // MARK: - Condensed

    private var condensedCard: some View {
        NavigationLink {
            ServerContainerListView(server: server)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(0.16))
                        .frame(width: 38, height: 38)

                    Image(systemName: "shippingbox")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(snapshot.containerRuntimeReachable ? Color.green : Color.secondary)
                            .frame(width: 5, height: 5)

                        condensedStatPills
                    }
                }

                Spacer(minLength: 8)

                if snapshot.containerRuntime != .none {
                    Text(snapshot.containerRuntime.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.12), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .cardBackground(accentColor: accentColor)
        }
        .buttonStyle(.plain)
    }

    private var condensedStatPills: some View {
        HStack(spacing: 5) {
            if snapshot.unhealthyContainerCount > 0 {
                condensedPill("\(snapshot.unhealthyContainerCount) unhealthy", tint: .red)
            } else if snapshot.restartingContainerCount > 0 {
                condensedPill("\(snapshot.restartingContainerCount) restarting", tint: .orange)
            }

            condensedPill("\(snapshot.runningContainerCount) running", tint: .green)

            Text("· \(snapshot.containerStatuses.count) total")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func condensedPill(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor.opacity(0.16))
                    .frame(width: 48, height: 48)

                Image(systemName: "shippingbox")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(server.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if snapshot.containerRuntime != .none {
                        Text(snapshot.containerRuntime.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accentColor.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(snapshot.containerRuntimeReachable ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)

                    Text(snapshot.containerRuntimeReachable ? "Runtime reachable" : "Runtime unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Stats

    private var statsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
            ContainerStatTile(label: "RUNNING", value: "\(snapshot.runningContainerCount)", tint: .green)

            if snapshot.pausedContainerCount > 0 {
                ContainerStatTile(label: "PAUSED", value: "\(snapshot.pausedContainerCount)", tint: .yellow)
            }

            if snapshot.unhealthyContainerCount > 0 {
                ContainerStatTile(label: "UNHEALTHY", value: "\(snapshot.unhealthyContainerCount)", tint: .red)
            }

            if snapshot.restartingContainerCount > 0 {
                ContainerStatTile(label: "RESTARTING", value: "\(snapshot.restartingContainerCount)", tint: .orange)
            }

            ContainerStatTile(label: "EXITED", value: "\(snapshot.exitedContainerCount)", tint: .secondary)
            ContainerStatTile(label: "TOTAL", value: "\(snapshot.containerStatuses.count)", tint: accentColor)
        }
        .padding(16)
    }

    // MARK: - Container Preview

    private var containersPreviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Active Containers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ForEach(Array(previewContainers.enumerated()), id: \.element.name) { index, container in
                NavigationLink {
                    ContainerDetailView(
                        server: server,
                        runtime: snapshot.containerRuntime,
                        containerName: container.name,
                        initialContainer: container
                    )
                } label: {
                    containerPreviewRow(container)
                }
                .buttonStyle(.plain)

                if index < previewContainers.count - 1 {
                    Divider()
                        .padding(.leading, 38)
                }
            }
        }
    }

    private func containerPreviewRow(_ container: ContainerStatusSnapshot) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(containerAccentColor(for: container))
                .frame(width: 8, height: 8)

            Text(container.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(container.healthLabel ?? container.state.capitalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(containerAccentColor(for: container))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(containerAccentColor(for: container).opacity(0.12), in: Capsule())

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - See All

    private var seeAllButton: some View {
        NavigationLink {
            ServerContainerListView(server: server)
        } label: {
            HStack {
                Text(snapshot.containerStatuses.isEmpty
                     ? "View Containers"
                     : "See All \(snapshot.containerStatuses.count) Containers")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(accentColor)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Tile

private struct ContainerStatTile: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        }
    }
}

// MARK: - Card Background Modifier

private extension View {
    func cardBackground(accentColor: Color) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.18),
                            accentColor.opacity(0.06),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

// MARK: - Helpers

private func containerEmptyStatePill(_ label: String, tint: Color) -> some View {
    Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
}

#Preview {
    let container = try! ModelContainer(
        for: Server.self,
        MetricSnapshot.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let server1 = Server(
        name: "prod-web-01",
        host: "192.168.1.100",
        port: 22,
        username: "admin",
        colorTag: "teal"
    )
    let server2 = Server(
        name: "staging-db",
        host: "192.168.1.101",
        port: 22,
        username: "deploy",
        colorTag: "indigo"
    )
    context.insert(server1)
    context.insert(server2)

    context.insert(MetricSnapshot(
        server: server1,
        recordedAt: .now,
        cpuPercent: 42,
        memUsedBytes: 3_600_000_000,
        memTotalBytes: 8_589_934_592,
        swapUsedBytes: 0,
        swapTotalBytes: 0,
        diskUsages: [],
        networkStats: [],
        containerRuntime: .docker,
        containerRuntimeReachable: true,
        containerStatuses: [
            ContainerStatusSnapshot(name: "api-server", image: "ghcr.io/myorg/api:latest", state: "running", status: "Up 3 days (healthy)"),
            ContainerStatusSnapshot(name: "worker", image: "myorg/worker:1.4", state: "running", status: "Up 3 days"),
            ContainerStatusSnapshot(name: "postgres", image: "postgres:16", state: "exited", status: "Exited (1) 12 minutes ago"),
            ContainerStatusSnapshot(name: "redis", image: "redis:7", state: "running", status: "Up 3 days (unhealthy)")
        ],
        loadAvg1m: 0.8,
        loadAvg5m: 0.7,
        loadAvg15m: 0.6,
        uptimeSeconds: 492_000
    ))

    context.insert(MetricSnapshot(
        server: server2,
        recordedAt: .now,
        cpuPercent: 12,
        memUsedBytes: 1_200_000_000,
        memTotalBytes: 4_294_967_296,
        swapUsedBytes: 0,
        swapTotalBytes: 0,
        diskUsages: [],
        networkStats: [],
        containerRuntime: .podman,
        containerRuntimeReachable: true,
        containerStatuses: [
            ContainerStatusSnapshot(name: "mysql", image: "mysql:8", state: "running", status: "Up 1 day"),
            ContainerStatusSnapshot(name: "backup-agent", image: "restic:latest", state: "paused", status: "Paused")
        ],
        loadAvg1m: 0.2,
        loadAvg5m: 0.2,
        loadAvg15m: 0.1,
        uptimeSeconds: 86_400
    ))

    return ContainersView()
        .modelContainer(container)
        .environment(SSHService.shared)
        .environment(
            MetricsPollingService(
                modelContext: context,
                sshService: .shared,
                liveActivityCoordinator: ServerHealthLiveActivityCoordinator()
            )
        )
}
