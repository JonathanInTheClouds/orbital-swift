//
//  TerminalListView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI

struct TerminalListView: View {
    @Environment(SSHService.self) private var sshService

    var body: some View {
        NavigationStack {
            Group {
                if sshService.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Terminal")
        }
    }

    // MARK: - Subviews

    private var sessionList: some View {
        List {
            ForEach(Array(sshService.sessions.values), id: \.id) { session in
                NavigationLink {
                    TerminalView(session: session)
                } label: {
                    SessionRow(session: session, status: sshService.status(for: session.serverID))
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        sshService.disconnect(serverID: session.serverID)
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
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
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: SSHSession
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "terminal")
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.serverName)
                    .font(.headline)
                StatusBadge(status: status)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TerminalListView()
        .environment(SSHService.shared)
}
