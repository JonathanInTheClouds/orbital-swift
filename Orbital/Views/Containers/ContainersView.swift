//
//  ContainersView.swift
//  Orbital
//
//  Created by Jonathan on 4/14/26.
//

import SwiftUI
import SwiftData

// MARK: - Container Entry

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

    @AppStorage("containerCardStyleByEntryID") private var cardStyleStorage = ""

    @State private var searchText = ""
    @State private var selectedFilter: ContainerListFilter = .all
    @State private var selectedServerID: UUID?
    @State private var actionError: IdentifiableError?

    var body: some View {
        NavigationStack {
            Group {
                if allEntries.isEmpty {
                    emptyState
                } else if filteredEntries.isEmpty {
                    filteredEmptyState
                } else {
                    containerList
                }
            }
            .scrollContentBackground(.hidden)
            .background(listBackground)
            .navigationTitle("Containers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Status", selection: $selectedFilter) {
                            ForEach(ContainerListFilter.allCases) { filter in
                                Label(filter.title, systemImage: filter.systemImage)
                                    .tag(filter)
                            }
                        }

                        Picker("Server", selection: $selectedServerID) {
                            Text("All Servers")
                                .tag(Optional<UUID>.none)

                            ForEach(availableServers, id: \.id) { server in
                                Text(server.name)
                                    .tag(Optional(server.id))
                            }
                        }
                    } label: {
                        Image(systemName: selectedFilter == .all && selectedServerID == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter containers")
                }
            }
            .searchable(text: $searchText, prompt: "Search containers")
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

    // MARK: - Container List

    private var containerList: some View {
        List {
            ForEach(filteredEntries) { entry in
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
                        style: cardStyle(for: entry.id)
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button {
                        toggleCardStyle(for: entry.id)
                    } label: {
                        Label(
                            cardStyle(for: entry.id) == .expanded ? "Condense" : "Detail",
                            systemImage: cardStyle(for: entry.id) == .expanded
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
                        toggleCardStyle(for: entry.id)
                    } label: {
                        Label(
                            cardStyle(for: entry.id) == .expanded ? "Show Condensed Card" : "Show Detailed Card",
                            systemImage: cardStyle(for: entry.id) == .expanded
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
        }
        .listStyle(.plain)
        .animation(.default, value: filteredEntries.map(\.id))
    }

    // MARK: - Empty State

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

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label(
                "No Matching Containers",
                systemImage: selectedFilter == .all && selectedServerID == nil ? "magnifyingglass" : "line.3.horizontal.decrease.circle"
            )
        } description: {
            if searchText.isEmpty {
                Text(noResultsDescription)
            } else {
                Text("No containers match “\(searchText)” with \(activeFilterDescription).")
            }
        } actions: {
            if selectedFilter != .all {
                Button("Show All Containers") {
                    selectedFilter = .all
                }
            }

            if selectedServerID != nil {
                Button("Show All Servers") {
                    selectedServerID = nil
                }
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

    // MARK: - Data

    private var latestSnapshotByServerID: [UUID: MetricSnapshot] {
        var result: [UUID: MetricSnapshot] = [:]
        for snapshot in snapshots {
            guard let serverID = snapshot.serverID, result[serverID] == nil else { continue }
            result[serverID] = snapshot
        }
        return result
    }

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
            guard selectedServerID == nil || entry.serverID == selectedServerID else { return false }
            guard !searchText.isEmpty else { return true }

            let q = searchText.lowercased()
            return entry.container.name.lowercased().contains(q) ||
                entry.container.image.lowercased().contains(q) ||
                entry.server.name.lowercased().contains(q)
        }
    }

    private var availableServers: [Server] {
        let serverIDsWithContainers = Set(allEntries.map(\.serverID))
        return servers.filter { serverIDsWithContainers.contains($0.id) }
    }

    private var selectedServerName: String? {
        guard let selectedServerID else { return nil }
        return availableServers.first(where: { $0.id == selectedServerID })?.name
    }

    private var activeFilterDescription: String {
        var parts: [String] = []

        if selectedFilter != .all {
            parts.append("the \(selectedFilter.title.lowercased()) filter")
        }

        if let selectedServerName {
            parts.append("server \(selectedServerName)")
        }

        return parts.isEmpty ? "the current filters" : parts.joined(separator: " and ")
    }

    private var noResultsDescription: String {
        if selectedFilter == .all, let selectedServerName {
            return "No containers are available for server \(selectedServerName)."
        }

        return "No containers match \(activeFilterDescription)."
    }

    // MARK: - Card Style

    private var cardStylesByEntryID: [String: String] {
        CardStylePreferenceStore.read(from: cardStyleStorage)
    }

    private func cardStyle(for entryID: String) -> ContainerCardStyle {
        guard let raw = cardStylesByEntryID[entryID],
              let style = ContainerCardStyle(rawValue: raw) else { return .compact }
        return style
    }

    private func toggleCardStyle(for entryID: String) {
        let next: ContainerCardStyle = cardStyle(for: entryID) == .expanded ? .compact : .expanded
        var styles = cardStylesByEntryID
        styles[entryID] = next.rawValue
        cardStyleStorage = CardStylePreferenceStore.write(styles)
    }

    // MARK: - Actions

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

    return ContainersView()
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
