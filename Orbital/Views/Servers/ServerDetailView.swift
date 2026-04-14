//
//  ServerDetailView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI

struct ServerDetailView: View {
    let server: Server

    @Environment(SSHService.self) private var sshService
    @State private var showEditServer = false
    @State private var connectError: IdentifiableError?
    @State private var navigateToTerminal = false

    var body: some View {
        List {
            // Header card
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "server.rack")
                            .font(.title2)
                            .foregroundStyle(accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(server.name)
                            .font(.headline)
                        Text("\(server.username)@\(server.host):\(server.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    StatusBadge(status: currentStatus)
                }
                .padding(.vertical, 4)
            }

            // Connection info
            Section("Connection") {
                LabeledRow(label: "Host", value: server.host)
                LabeledRow(label: "Port", value: "\(server.port)")
                LabeledRow(label: "Username", value: server.username)
                LabeledRow(label: "Auth", value: server.authMethod.displayName)
                if let jumpHost = server.jumpHostRef, !jumpHost.isEmpty {
                    LabeledRow(label: "Jump Host", value: jumpHost)
                }
            }

            // Metadata
            if !server.tags.isEmpty || !server.notes.isEmpty {
                Section("Details") {
                    if !server.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tags")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(server.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                        }
                    }
                    if !server.notes.isEmpty {
                        LabeledRow(label: "Notes", value: server.notes)
                    }
                }
            }

            // Actions
            Section {
                Button {
                    Task { await connectAndOpenTerminal() }
                } label: {
                    Label(
                        currentStatus == .connected ? "Open Terminal" : "Connect & Open Terminal",
                        systemImage: "terminal"
                    )
                }
                .disabled(currentStatus == .connecting)

                if currentStatus == .connected {
                    Button(role: .destructive) {
                        sshService.disconnect(serverID: server.id)
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditServer = true }
            }
        }
        .sheet(isPresented: $showEditServer) {
            AddEditServerView(server: server)
        }
        .navigationDestination(isPresented: $navigateToTerminal) {
            if let session = sshService.session(for: server.id) {
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

    // MARK: - Helpers

    private var currentStatus: ConnectionStatus {
        sshService.status(for: server.id)
    }

    private var accentColor: Color {
        serverAccentColor(server.colorTag)
    }

    private func connectAndOpenTerminal() async {
        do {
            if currentStatus != .connected {
                _ = try await sshService.connect(to: server)
            }
            navigateToTerminal = true
        } catch {
            connectError = IdentifiableError(message: error.localizedDescription)
        }
    }
}

// MARK: - LabeledRow

struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - FlowLayout

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
    NavigationStack {
        ServerDetailView(
            server: Server(
                name: "prod-web-01",
                host: "192.168.1.100",
                port: 22,
                username: "admin",
                tags: ["production", "web"],
                notes: "Primary web server in us-east-1."
            )
        )
    }
    .environment(SSHService.shared)
}
