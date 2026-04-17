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

    @Query(sort: \Server.name) private var servers: [Server]

    @AppStorage("terminalCardStyleBySessionID") private var cardStyleStorage = ""

    @State private var searchText = ""
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
            }
            .searchable(text: $searchText, prompt: "Search sessions")
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
                        connectedAt: session.createdAt,
                        style: cardStyle(for: session.id)
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button {
                        toggleCardStyle(for: session.id)
                    } label: {
                        Label(
                            cardStyle(for: session.id) == .expanded ? "Condense" : "Detail",
                            systemImage: cardStyle(for: session.id) == .expanded
                                ? "rectangle.compress.vertical"
                                : "rectangle.grid.1x2"
                        )
                    }
                    .tint(.indigo)

                    Button(role: .destructive) {
                        disconnect(session)
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
                .contextMenu {
                    Button {
                        toggleCardStyle(for: session.id)
                    } label: {
                        Label(
                            cardStyle(for: session.id) == .expanded ? "Show Condensed Card" : "Show Detailed Card",
                            systemImage: cardStyle(for: session.id) == .expanded
                                ? "rectangle.compress.vertical"
                                : "rectangle.grid.1x2"
                        )
                    }

                    Divider()

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
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.teal.opacity(0.14))
                            .frame(width: 88, height: 88)

                        Image(systemName: "apple.terminal.on.rectangle")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.teal)
                    }

                    VStack(spacing: 8) {
                        Text("No Active Sessions")
                            .font(.title2.weight(.bold))

                        Text(servers.isEmpty
                             ? "Add a server first, then open a terminal session when you are ready to connect."
                             : "Start a fresh terminal whenever you need one. Existing servers are ready to launch from here.")
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
                            Button {
                                showNewSession = true
                            } label: {
                                Label("Open New Session", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        HStack(spacing: 8) {
                            terminalEmptyStatePill("Separate Sessions", tint: .teal)
                            terminalEmptyStatePill("Reconnect Fast", tint: .indigo)
                            terminalEmptyStatePill("Session History", tint: .cyan)
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
                                    Color.teal.opacity(0.18),
                                    Color.teal.opacity(0.05),
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

    private var cardStylesBySessionID: [String: String] {
        CardStylePreferenceStore.read(from: cardStyleStorage)
    }

    private var filteredSessions: [SSHSession] {
        let all = Array(sshService.sessions.values).sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
        guard !searchText.isEmpty else { return all }
        let query = searchText.lowercased()
        return all.filter {
            $0.serverName.lowercased().contains(query) ||
            $0.displayTitle.lowercased().contains(query)
        }
    }

    private var serversByID: [UUID: Server] {
        Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
    }

    private func cardStyle(for sessionID: UUID) -> TerminalCardStyle {
        guard let rawValue = cardStylesBySessionID[sessionID.uuidString],
              let style = TerminalCardStyle(rawValue: rawValue) else {
            return .compact
        }

        return style
    }

    private func toggleCardStyle(for sessionID: UUID) {
        let nextStyle: TerminalCardStyle = cardStyle(for: sessionID) == .expanded ? .compact : .expanded
        var styles = cardStylesBySessionID
        styles[sessionID.uuidString] = nextStyle.rawValue
        cardStyleStorage = CardStylePreferenceStore.write(styles)
    }

    private func disconnect(_ session: SSHSession) {
        withAnimation {
            var styles = cardStylesBySessionID
            styles.removeValue(forKey: session.id.uuidString)
            cardStyleStorage = CardStylePreferenceStore.write(styles)
            sshService.disconnect(sessionID: session.id)
        }
    }
}

private func terminalEmptyStatePill(_ label: String, tint: Color) -> some View {
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

    return TerminalListView()
        .modelContainer(container)
        .environment(SSHService.shared)
}
