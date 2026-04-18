//
//  ContainerDetailView.swift
//  Orbital
//
//  Created by Jonathan on 4/16/26.
//

import SwiftUI

// MARK: - Shell Quoting (module-scope, shared with ContainersView)

func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
}

func shellCommandWithContainerRuntimePath(_ command: String) -> String {
    "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"; \(command)"
}

// MARK: - Container Action

enum ContainerAction: Equatable {
    case start
    case stop
    case restart
    case pause
    case unpause
    case kill
    case remove

    var title: String {
        switch self {
        case .start:   return "Start"
        case .stop:    return "Stop"
        case .restart: return "Restart"
        case .pause:   return "Pause"
        case .unpause: return "Unpause"
        case .kill:    return "Kill"
        case .remove:  return "Remove"
        }
    }

    var systemImage: String {
        switch self {
        case .start:   return "play.fill"
        case .stop:    return "stop.fill"
        case .restart: return "arrow.clockwise"
        case .pause:   return "pause.fill"
        case .unpause: return "play.fill"
        case .kill:    return "xmark.octagon.fill"
        case .remove:  return "trash.fill"
        }
    }

    func command(for containerName: String, runtime: ContainerRuntimeKind) -> String {
        let rt = runtime.rawValue
        let q = shellQuoted(containerName)
        switch self {
        case .start:   return shellCommandWithContainerRuntimePath("\(rt) start \(q)")
        case .stop:    return shellCommandWithContainerRuntimePath("\(rt) stop \(q)")
        case .restart: return shellCommandWithContainerRuntimePath("\(rt) restart \(q)")
        case .pause:   return shellCommandWithContainerRuntimePath("\(rt) pause \(q)")
        case .unpause: return shellCommandWithContainerRuntimePath("\(rt) unpause \(q)")
        case .kill:    return shellCommandWithContainerRuntimePath("\(rt) kill \(q)")
        case .remove:  return shellCommandWithContainerRuntimePath("\(rt) rm -f \(q)")
        }
    }
}

// MARK: - Detail View

struct ContainerDetailView: View {
    let server: Server
    let runtime: ContainerRuntimeKind

    // The canonical name used to query/act on the container
    let containerName: String

    @Environment(SSHService.self) private var sshService
    @Environment(MetricsPollingService.self) private var metricsPollingService
    @Environment(\.dismiss) private var dismiss

    @State private var container: ContainerStatusSnapshot?
    @State private var isPerformingAction = false
    @State private var isRefreshing = false
    @State private var actionError: IdentifiableError?
    @State private var confirmKill = false
    @State private var confirmRemove = false
    @State private var logs: String?
    @State private var isLoadingLogs = false

    init(
        server: Server,
        runtime: ContainerRuntimeKind,
        containerName: String,
        initialContainer: ContainerStatusSnapshot? = nil
    ) {
        self.server = server
        self.runtime = runtime
        self.containerName = containerName
        _container = State(initialValue: initialContainer)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                detailsSection
                actionsSection
                logsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .refreshable { await refreshContainer() }
        .task { await refreshContainer() }
        .background(backgroundGradient)
        .navigationTitle(container?.name ?? containerName)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Container Action Failed",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError?.message ?? "")
        }
        .confirmationDialog(
            "Kill Container?",
            isPresented: $confirmKill,
            titleVisibility: .visible
        ) {
            Button("Kill", role: .destructive) {
                Task { await performAction(.kill) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Forcefully terminate this container process. Data may be lost.")
        }
        .confirmationDialog(
            "Remove Container?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await performAction(.remove) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently delete this container. This cannot be undone.")
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 60, height: 60)

                    Image(systemName: "shippingbox")
                        .font(.title2)
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(container?.name ?? containerName)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)

                    Text(server.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let container {
                        HStack(spacing: 6) {
                            statePill(for: container)

                            if let health = container.healthLabel {
                                Text(health)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(accentColor.opacity(0.12), in: Capsule())
                            }
                        }
                    } else {
                        Text("Loading…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.20),
                            accentColor.opacity(0.08),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        DetailCardSection(title: "Details", subtitle: "Container runtime and image information") {
            VStack(spacing: 0) {
                LabeledRow(label: "Runtime", value: runtime.displayName)
                Divider().padding(.vertical, 8)
                LabeledRow(label: "Image", value: container?.image ?? "—")
                Divider().padding(.vertical, 8)
                LabeledRow(label: "State", value: container?.state.capitalized ?? "—")
                Divider().padding(.vertical, 8)
                LabeledRow(label: "Status", value: container?.status ?? "—")
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        DetailCardSection(title: "Actions", subtitle: "Lifecycle controls for this container") {
            VStack(spacing: 10) {
                if let container {
                    actionButton("Restart", systemImage: "arrow.clockwise", tint: .blue) {
                        Task { await performAction(.restart) }
                    }
                    .disabled(isBusy)

                    if container.isRunning || container.isPaused || container.isRestarting {
                        actionButton("Stop", systemImage: "stop.fill", tint: .orange) {
                            Task { await performAction(.stop) }
                        }
                        .disabled(isBusy)
                    }

                    if container.isExited {
                        actionButton("Start", systemImage: "play.fill", tint: .green) {
                            Task { await performAction(.start) }
                        }
                        .disabled(isBusy)
                    }

                    if container.isRunning {
                        actionButton("Pause", systemImage: "pause.fill", tint: .yellow) {
                            Task { await performAction(.pause) }
                        }
                        .disabled(isBusy)
                    }

                    if container.isPaused {
                        actionButton("Unpause", systemImage: "play.fill", tint: .green) {
                            Task { await performAction(.unpause) }
                        }
                        .disabled(isBusy)
                    }

                    Divider()

                    actionButton("Kill", systemImage: "xmark.octagon.fill", tint: .red) {
                        confirmKill = true
                    }
                    .disabled(isBusy)

                    actionButton("Remove Container", systemImage: "trash.fill", tint: .red) {
                        confirmRemove = true
                    }
                    .disabled(isBusy)
                } else {
                    Text("Container state unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        DetailCardSection(title: "Logs", subtitle: "Last 200 lines from container output") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Task { await loadLogs() }
                } label: {
                    HStack {
                        if isLoadingLogs {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        Text(isLoadingLogs ? "Loading…" : (logs == nil ? "Load Logs" : "Refresh Logs"))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingLogs || runtime == .none)

                if let logs {
                    ScrollView(.vertical) {
                        Text(logs)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 280)
                    .background(
                        Color(uiColor: .tertiarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func statePill(for c: ContainerStatusSnapshot) -> some View {
        let label: String
        if let health = c.healthLabel {
            label = health
        } else {
            label = c.state.capitalized
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(containerAccentColor(for: c))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(containerAccentColor(for: c).opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                if isPerformingAction {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                }
                Text(title)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private var accentColor: Color {
        container.map { containerAccentColor(for: $0) } ?? .cyan
    }

    private var isBusy: Bool {
        isPerformingAction || isRefreshing || runtime == .none
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                accentColor.opacity(0.10),
                Color(uiColor: .systemBackground),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Data Operations

    private func refreshContainer() async {
        guard runtime != .none else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await sshService.runCommand(containerStatusCommand(for: containerName), on: server)
            guard result.exitStatus == 0 else {
                let message = result.standardErrorString.trimmingCharacters(in: .whitespacesAndNewlines)
                actionError = IdentifiableError(
                    message: message.isEmpty ? "Failed to load current container status." : message
                )
                return
            }
            container = parseContainer(from: result.standardOutputString, fallbackName: containerName)
        } catch {
            actionError = IdentifiableError(message: error.localizedDescription)
        }
    }

    private func performAction(_ action: ContainerAction) async {
        guard runtime != .none else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let result = try await sshService.runCommand(
                action.command(for: containerName, runtime: runtime),
                on: server
            )
            guard result.exitStatus == 0 else {
                let message = result.standardErrorString.trimmingCharacters(in: .whitespacesAndNewlines)
                actionError = IdentifiableError(
                    message: message.isEmpty
                        ? "\(action.title) failed with status \(result.exitStatus)."
                        : message
                )
                return
            }

            if action == .remove {
                try? await metricsPollingService.pollNow(server: server)
                dismiss()
                return
            }

            try? await metricsPollingService.pollNow(server: server)
            await refreshContainer()
        } catch {
            actionError = IdentifiableError(message: error.localizedDescription)
        }
    }

    private func loadLogs() async {
        guard runtime != .none else { return }

        isLoadingLogs = true
        defer { isLoadingLogs = false }

        do {
            let cmd = shellCommandWithContainerRuntimePath(
                "\(runtime.rawValue) logs --tail 200 \(shellQuoted(containerName)) 2>&1"
            )
            let result = try await sshService.runCommand(cmd, on: server)
            logs = result.standardOutputString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "(no output)"
                : result.standardOutputString
        } catch {
            actionError = IdentifiableError(message: error.localizedDescription)
        }
    }

    private func containerStatusCommand(for name: String) -> String {
        let filter = "name=^/\(name)$"
        return shellCommandWithContainerRuntimePath(
            "\(runtime.rawValue) ps -a --filter \(shellQuoted(filter)) --format '{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}'"
        )
    }

    private func parseContainer(from output: String, fallbackName: String) -> ContainerStatusSnapshot? {
        guard let firstLine = output
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        else {
            return nil
        }

        let parts = firstLine.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return ContainerStatusSnapshot(
                name: fallbackName,
                image: "",
                state: "unknown",
                status: firstLine
            )
        }

        return ContainerStatusSnapshot(
            name: String(parts[0]),
            image: String(parts[1]),
            state: String(parts[2]),
            status: String(parts[3])
        )
    }
}
