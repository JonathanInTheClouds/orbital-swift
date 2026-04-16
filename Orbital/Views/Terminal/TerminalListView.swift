//
//  TerminalListView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI
import SwiftData

struct TerminalListView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Server.name) private var servers: [Server]

    @AppStorage("terminalListCardStyle") private var cardStyleRawValue = TerminalCardStyle.expanded.rawValue

    @State private var searchText = ""
    @State private var sessionConnectedAt: [UUID: Date] = [:]
    @State private var disconnectError: IdentifiableError?
    @State private var showNewSession = false
    /// Held here until the sheet fully dismisses, then promoted to `launchedSession`.
    @State private var pendingLaunch: SSHSession?
    /// Drives programmatic navigation to the terminal after the sheet is gone.
    @State private var launchedSession: SSHSession?

    var body: some View {
        NavigationStack {
            Group {
                if filteredSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .scrollContentBackground(.hidden)
            .background(listBackground)
            .navigationTitle("Terminals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewSession = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Card Layout") {
                            Button {
                                cardStyle = .expanded
                            } label: {
                                Label(
                                    "Detailed",
                                    systemImage: cardStyle == .expanded
                                        ? "checkmark.circle.fill"
                                        : "rectangle.grid.1x2"
                                )
                            }

                            Button {
                                cardStyle = .compact
                            } label: {
                                Label(
                                    "Condensed",
                                    systemImage: cardStyle == .compact
                                        ? "checkmark.circle.fill"
                                        : "rectangle.compress.vertical"
                                )
                            }
                        }
                    } label: {
                        Image(
                            systemName: cardStyle == .expanded
                                ? "rectangle.grid.1x2"
                                : "rectangle.compress.vertical"
                        )
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search sessions")
            .task {
                // Seed timestamps for any sessions already open when the view first appears
                for id in sshService.sessions.keys where sessionConnectedAt[id] == nil {
                    sessionConnectedAt[id] = .now
                }
            }
            .onChange(of: sessionIDs) { oldIDs, newIDs in
                let added   = Set(newIDs).subtracting(oldIDs)
                let removed = Set(oldIDs).subtracting(newIDs)

                for id in added   where sessionConnectedAt[id] == nil { sessionConnectedAt[id] = .now }
                for id in removed { sessionConnectedAt.removeValue(forKey: id) }
            }
            .alert("Disconnect Error", isPresented: Binding(
                get: { disconnectError != nil },
                set: { if !$0 { disconnectError = nil } }
            )) {
                Button("OK") { disconnectError = nil }
            } message: {
                Text(disconnectError?.message ?? "")
            }
            .sheet(isPresented: $showNewSession) {
                TerminalNewSessionSheet { session in
                    pendingLaunch = session
                }
            }
            // Wait until the sheet has fully dismissed before navigating so the
            // terminal opens on the main stack — back goes to the session list.
            .onChange(of: showNewSession) { _, isShowing in
                if !isShowing, let session = pendingLaunch {
                    launchedSession = session
                    pendingLaunch = nil
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { launchedSession != nil },
                set: { if !$0 { launchedSession = nil } }
            )) {
                if let session = launchedSession {
                    TerminalView(session: session)
                }
            }
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(filteredSessions) { session in
                NavigationLink {
                    TerminalView(session: session)
                } label: {
                    TerminalSessionCardView(
                        session: session,
                        status: sshService.status(for: session.serverID),
                        server: serversByID[session.serverID],
                        connectedAt: sessionConnectedAt[session.serverID] ?? .now,
                        style: cardStyle
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        disconnect(session)
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
                .contextMenu {
                    Button {
                        // Navigate handled by NavigationLink — open terminal from context menu
                    } label: {
                        Label("Open Terminal", systemImage: "apple.terminal.on.rectangle")
                    }

                    Divider()

                    Button(role: .destructive) {
                        disconnect(session)
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .listStyle(.plain)
        .animation(.default, value: filteredSessions.map(\.id))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "apple.terminal.on.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("No Active Sessions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect to a server from the Servers tab to open a terminal session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }

    // MARK: - Helpers

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

    private var cardStyle: TerminalCardStyle {
        get { TerminalCardStyle(rawValue: cardStyleRawValue) ?? .expanded }
        nonmutating set { cardStyleRawValue = newValue.rawValue }
    }

    private var sessionIDs: [UUID] {
        Array(sshService.sessions.keys).sorted()
    }

    private var filteredSessions: [SSHSession] {
        let all = Array(sshService.sessions.values)
        guard !searchText.isEmpty else { return all }
        let query = searchText.lowercased()
        return all.filter { $0.serverName.lowercased().contains(query) }
    }

    private var serversByID: [UUID: Server] {
        Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
    }

    private func disconnect(_ session: SSHSession) {
        withAnimation {
            sshService.disconnect(serverID: session.serverID)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Server.self,
        MetricSnapshot.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    return TerminalListView()
        .modelContainer(container)
        .environment(SSHService.shared)
}
