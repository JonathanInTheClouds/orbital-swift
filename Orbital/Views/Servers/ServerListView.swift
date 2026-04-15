//
//  ServerListView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI
import SwiftData

struct ServerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SSHService.self) private var sshService
    @Environment(MetricsPollingService.self) private var metricsPollingService

    @AppStorage("serverListCardStyle") private var cardStyleRawValue = ServerCardStyle.expanded.rawValue

    @Query(sort: \Server.name) private var servers: [Server]
    @Query(sort: \MetricSnapshot.recordedAt, order: .reverse) private var snapshots: [MetricSnapshot]

    @State private var showAddServer = false
    @State private var serverToEdit: Server?
    @State private var searchText = ""
    @State private var connectError: IdentifiableError?

    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Card Layout") {
                            Button {
                                cardStyle = .expanded
                            } label: {
                                Label("Detailed", systemImage: cardStyle == .expanded ? "checkmark.circle.fill" : "rectangle.grid.1x2")
                            }

                            Button {
                                cardStyle = .compact
                            } label: {
                                Label("Condensed", systemImage: cardStyle == .compact ? "checkmark.circle.fill" : "rectangle.compress.vertical")
                            }
                        }
                    } label: {
                        Image(systemName: cardStyle == .expanded ? "rectangle.grid.1x2" : "rectangle.compress.vertical")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddServer = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
            }
            .onChange(of: serverIDs) { _, _ in
                metricsPollingService.ensureAutomaticPolling(for: servers)
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
    }

    // MARK: - Subviews

    private var serverList: some View {
        List {
            ForEach(filteredServers) { server in
                NavigationLink {
                    ServerDetailView(server: server)
                } label: {
                    ServerCardView(
                        server: server,
                        status: sshService.status(for: server.id),
                        latestSnapshot: latestSnapshot(for: server.id),
                        isPolling: metricsPollingService.isPolling(serverID: server.id),
                        lastError: metricsPollingService.lastError(for: server.id),
                        style: cardStyle
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading) {
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
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("No Servers")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap + to add your first Linux server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Add Server") {
                showAddServer = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding()
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

    private var cardStyle: ServerCardStyle {
        get { ServerCardStyle(rawValue: cardStyleRawValue) ?? .expanded }
        nonmutating set { cardStyleRawValue = newValue.rawValue }
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

    private func connectToServer(_ server: Server) async {
        do {
            _ = try await sshService.connect(to: server)
        } catch {
            connectError = IdentifiableError(message: error.localizedDescription)
        }
    }

    private func delete(_ server: Server) {
        withAnimation {
            modelContext.delete(server)
        }
    }
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

    return ServerListView()
        .modelContainer(container)
        .environment(SSHService.shared)
        .environment(MetricsPollingService(modelContext: container.mainContext, sshService: .shared))
}
