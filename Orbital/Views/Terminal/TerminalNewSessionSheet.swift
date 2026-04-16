//
//  TerminalNewSessionSheet.swift
//  Orbital
//
//  Created by Jonathan on 4/15/26.
//

import SwiftUI
import SwiftData

struct TerminalNewSessionSheet: View {
    /// Called with the new session once connected. The sheet dismisses itself immediately after.
    var onConnect: (SSHSession) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(SSHService.self) private var sshService
    @Query(sort: \Server.name) private var servers: [Server]

    @State private var searchText = ""
    @State private var connectingID: UUID?
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
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search servers")
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

    // MARK: - Server List

    private var serverList: some View {
        List {
            ForEach(filteredServers) { server in
                Button {
                    Task { await connect(to: server) }
                } label: {
                    ConnectServerRow(
                        server: server,
                        status: serverDisplayStatus(
                            sessionStatus: sshService.status(for: server.id),
                            lastReachableAt: [server.lastSeenAt, sshService.lastReachableAt(for: server.id)]
                                .compactMap { $0 }
                                .max()
                        ),
                        activeSessionCount: sshService.activeSessionCount(for: server.id),
                        isConnecting: connectingID == server.id
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .disabled(connectingID != nil)
            }
        }
        .listStyle(.plain)
        .animation(.default, value: filteredServers.map(\.id))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("No Servers")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add a server from the Servers tab to get started.")
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

    private var filteredServers: [Server] {
        guard !searchText.isEmpty else { return servers }
        let q = searchText.lowercased()
        return servers.filter {
            $0.name.lowercased().contains(q) ||
            $0.host.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    private func connect(to server: Server) async {
        connectingID = server.id
        defer { connectingID = nil }
        do {
            let session = try await sshService.createSession(to: server)
            onConnect(session)
            dismiss()
        } catch {
            connectError = IdentifiableError(message: error.localizedDescription)
        }
    }
}

// MARK: - Connect Server Row

private struct ConnectServerRow: View {
    let server: Server
    let status: ConnectionStatus
    let activeSessionCount: Int
    let isConnecting: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor.opacity(0.16))
                    .frame(width: 48, height: 48)

                if isConnecting {
                    ProgressView()
                        .tint(accentColor)
                } else {
                    Image(systemName: "server.rack")
                        .font(.headline)
                        .foregroundStyle(accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(server.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    if isConnecting {
                        Text("Connecting…")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.yellow.opacity(0.12), in: Capsule())
                    } else {
                        StatusBadge(status: status)
                    }
                }

                Text("\(server.username)@\(server.host):\(server.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if activeSessionCount > 0 {
                        Text(activeSessionCount == 1 ? "1 Session" : "\(activeSessionCount) Sessions")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.green.opacity(0.12), in: Capsule())
                    }

                    if server.osKind != .unknown {
                        Text(server.osKind.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.secondary.opacity(0.10), in: Capsule())
                    }
                }

                if !server.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(server.tags.prefix(3)), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.06), in: Capsule())
                        }
                        if server.tags.count > 3 {
                            Text("+\(server.tags.count - 3)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
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
        )
    }

    private var accentColor: Color {
        serverAccentColor(server.colorTag)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Server.self,
        MetricSnapshot.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return TerminalNewSessionSheet()
        .modelContainer(container)
        .environment(SSHService.shared)
}
