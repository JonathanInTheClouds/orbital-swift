//
//  ServerListView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI
import SwiftData

struct ServerListView: View {
    @Binding var requestedServerID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(SSHService.self) private var sshService
    @Environment(MetricsPollingService.self) private var metricsPollingService

    @AppStorage("serverCardStyleByServerID") private var cardStyleStorage = ""

    @Query(sort: \Server.name) private var servers: [Server]
    @Query(sort: \MetricSnapshot.recordedAt, order: .reverse) private var snapshots: [MetricSnapshot]

    @State private var showAddServer = false
    @State private var serverToEdit: Server?
    @State private var searchText = ""
    @State private var connectError: IdentifiableError?
    @State private var navigationPath: [UUID] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if servers.isEmpty {
                    emptyState
                } else {
                    serverList
                }
            }
            .scrollContentBackground(.hidden)
            .background(listBackground)
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddServer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("servers.addToolbarButton")
                }
            }
            .searchable(text: $searchText, prompt: "Search servers")
            .sheet(isPresented: $showAddServer) {
                AddEditServerView()
            }
            .sheet(item: $serverToEdit) { server in
                AddEditServerView(server: server)
            }
            .task {
                metricsPollingService.ensureAutomaticPolling(for: servers)
                consumeRequestedServerIDIfNeeded()
            }
            .onChange(of: serverIDs) { _, _ in
                metricsPollingService.ensureAutomaticPolling(for: servers)
                consumeRequestedServerIDIfNeeded()
            }
            .onChange(of: requestedServerID) { _, _ in
                consumeRequestedServerIDIfNeeded()
            }
            .alert("Connection Error", isPresented: Binding(
                get: { connectError != nil },
                set: { if !$0 { connectError = nil } }
            )) {
                Button("OK") { connectError = nil }
            } message: {
                Text(connectError?.message ?? "")
            }
            .navigationDestination(for: UUID.self) { serverID in
                if let server = servers.first(where: { $0.id == serverID }) {
                    ServerDetailView(server: server)
                } else {
                    ContentUnavailableView("Server Not Found", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    // MARK: - Subviews

    private var serverList: some View {
        List {
            ForEach(filteredServers) { server in
                NavigationLink(value: server.id) {
                    ServerCardView(
                        server: server,
                        status: displayStatus(for: server),
                        latestSnapshot: latestSnapshot(for: server.id),
                        isPolling: metricsPollingService.isPolling(serverID: server.id),
                        lastError: metricsPollingService.lastError(for: server.id),
                        style: cardStyle(for: server.id)
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading) {
                    Button {
                        toggleCardStyle(for: server.id)
                    } label: {
                        Label(
                            cardStyle(for: server.id) == .expanded ? "Condense" : "Detail",
                            systemImage: cardStyle(for: server.id) == .expanded
                                ? "rectangle.compress.vertical"
                                : "rectangle.grid.1x2"
                        )
                    }
                    .tint(.indigo)

                    Button {
                        Task { await connectToServer(server) }
                    } label: {
                        Label("Connect", systemImage: "terminal")
                    }
                    .tint(.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        delete(server)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        serverToEdit = server
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    Button {
                        toggleCardStyle(for: server.id)
                    } label: {
                        Label(
                            cardStyle(for: server.id) == .expanded ? "Show Condensed Card" : "Show Detailed Card",
                            systemImage: cardStyle(for: server.id) == .expanded
                                ? "rectangle.compress.vertical"
                                : "rectangle.grid.1x2"
                        )
                    }

                    Divider()

                    Button {
                        Task { await connectToServer(server) }
                    } label: {
                        Label("Open Terminal", systemImage: "terminal")
                    }

                    Button {
                        serverToEdit = server
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        delete(server)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .animation(.default, value: filteredServers.map(\.id))
    }

    private var emptyState: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(accentColor.opacity(0.14))
                            .frame(width: 88, height: 88)

                        Image(systemName: "server.rack")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }

                    VStack(spacing: 8) {
                        Text("No Servers Yet")
                            .font(.title2.weight(.bold))
                            .accessibilityIdentifier("servers.empty.title")

                        Text("Add your first machine to start monitoring metrics, launching terminals, and managing everything from one place.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        Button {
                            showAddServer = true
                        } label: {
                            Label("Add Your First Server", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("servers.empty.addButton")

                        HStack(spacing: 8) {
                            emptyStatePill("SSH Access", tint: accentColor)
                            emptyStatePill("Live Metrics", tint: .cyan)
                            emptyStatePill("Saved Sessions", tint: .indigo)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: 440)
                .background {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.18),
                                    accentColor.opacity(0.05),
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
                .accessibilityIdentifier("servers.empty.state")
            }
        }
    }

    // MARK: - Helpers

    private var filteredServers: [Server] {
        guard !searchText.isEmpty else { return servers }
        let query = searchText.lowercased()
        return servers.filter {
            $0.name.lowercased().contains(query) ||
            $0.host.lowercased().contains(query) ||
            $0.tags.contains { $0.lowercased().contains(query) }
        }
    }

    private var serverIDs: [UUID] {
        servers.map(\.id)
    }

    private func consumeRequestedServerIDIfNeeded() {
        guard let requestedServerID,
              servers.contains(where: { $0.id == requestedServerID }) else {
            return
        }

        navigationPath = [requestedServerID]
        self.requestedServerID = nil
    }

    private var cardStylesByServerID: [String: String] {
        CardStylePreferenceStore.read(from: cardStyleStorage)
    }

    private var latestSnapshotByServerID: [UUID: MetricSnapshot] {
        var results: [UUID: MetricSnapshot] = [:]

        for snapshot in snapshots {
            guard let serverID = snapshot.server?.id, results[serverID] == nil else { continue }
            results[serverID] = snapshot
        }

        return results
    }

    private var listBackground: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                .teal.opacity(0.06),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func latestSnapshot(for serverID: UUID) -> MetricSnapshot? {
        latestSnapshotByServerID[serverID]
    }

    private var accentColor: Color {
        .teal
    }

    private func displayStatus(for server: Server) -> ConnectionStatus {
        serverDisplayStatus(
            sessionStatus: sshService.status(for: server.id),
            lastReachableAt: lastReachableAt(for: server)
        )
    }

    private func lastReachableAt(for server: Server) -> Date? {
        [
            server.lastSeenAt,
            metricsPollingService.lastRecordedAt(for: server.id),
            sshService.lastReachableAt(for: server.id)
        ]
        .compactMap { $0 }
        .max()
    }

    private func connectToServer(_ server: Server) async {
        do {
            _ = try await sshService.createSession(to: server)
        } catch {
            connectError = IdentifiableError(message: error.localizedDescription)
        }
    }

    private func cardStyle(for serverID: UUID) -> ServerCardStyle {
        guard let rawValue = cardStylesByServerID[serverID.uuidString],
              let style = ServerCardStyle(rawValue: rawValue) else {
            return .compact
        }

        return style
    }

    private func toggleCardStyle(for serverID: UUID) {
        let nextStyle: ServerCardStyle = cardStyle(for: serverID) == .expanded ? .compact : .expanded
        var styles = cardStylesByServerID
        styles[serverID.uuidString] = nextStyle.rawValue
        cardStyleStorage = CardStylePreferenceStore.write(styles)
    }

    private func delete(_ server: Server) {
        withAnimation {
            var styles = cardStylesByServerID
            styles.removeValue(forKey: server.id.uuidString)
            cardStyleStorage = CardStylePreferenceStore.write(styles)
            modelContext.delete(server)
        }
    }
}

private func emptyStatePill(_ label: String, tint: Color) -> some View {
    Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
}

// MARK: - Helpers

struct IdentifiableError: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    let container = try! ModelContainer(
        for: Server.self,
        MetricSnapshot.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    return ServerListView(requestedServerID: .constant(nil))
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
