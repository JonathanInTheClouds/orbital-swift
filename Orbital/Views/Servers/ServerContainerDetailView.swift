//
//  ServerContainerDetailView.swift
//  Orbital
//
//  Created by Jonathan on 4/14/26.
//

import SwiftUI

struct ServerContainerDetailView: View {
    let server: Server
    let runtime: ContainerRuntimeKind

    @Environment(SSHService.self) private var sshService
    @Environment(MetricsPollingService.self) private var metricsPollingService

    @State private var container: ContainerStatusSnapshot?
    @State private var isPerformingAction = false
    @State private var isRefreshing = false
    @State private var actionError: String?

    init(server: Server, runtime: ContainerRuntimeKind, container: ContainerStatusSnapshot) {
        self.server = server
        self.runtime = runtime
        _container = State(initialValue: container)
    }

    var body: some View {
        List {
            if let container {
                Section {
                    LabeledContent("Runtime", value: runtime.displayName)
                    LabeledContent("Name", value: container.name)
                    LabeledContent("Image", value: container.image)
                    LabeledContent("State", value: container.state.capitalized)
                    LabeledContent("Status", value: container.status)
                }

                Section("Actions") {
                    Button {
                        Task { await performAction(.restart) }
                    } label: {
                        actionLabel("Restart", systemImage: "arrow.clockwise")
                    }
                    .disabled(isBusy)

                    if container.isRunning || container.isPaused || container.isRestarting {
                        Button(role: .destructive) {
                            Task { await performAction(.stop) }
                        } label: {
                            actionLabel("Stop", systemImage: "stop.fill")
                        }
                        .disabled(isBusy)
                    } else {
                        Button {
                            Task { await performAction(.start) }
                        } label: {
                            actionLabel("Start", systemImage: "play.fill")
                        }
                        .disabled(isBusy)
                    }
                }
            } else {
                Section {
                    Text("This container is no longer present in the latest runtime output.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(container?.name ?? "Container")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshContainer()
        }
        .refreshable {
            await refreshContainer()
        }
        .alert("Container Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var isBusy: Bool {
        isPerformingAction || isRefreshing || runtime == .none
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
        }
    }

    private func refreshContainer() async {
        guard runtime != .none, let name = container?.name else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await sshService.runCommand(containerStatusCommand(for: name), on: server)
            guard result.exitStatus == 0 else {
                let message = result.standardErrorString.trimmingCharacters(in: .whitespacesAndNewlines)
                actionError = message.isEmpty ? "Failed to load current container status." : message
                return
            }

            container = parseContainer(from: result.standardOutputString, fallbackName: name)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func performAction(_ action: ContainerAction) async {
        guard runtime != .none, let name = container?.name else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let result = try await sshService.runCommand(action.command(for: name, runtime: runtime), on: server)
            guard result.exitStatus == 0 else {
                let message = result.standardErrorString.trimmingCharacters(in: .whitespacesAndNewlines)
                actionError = message.isEmpty
                    ? "\(action.title) failed with status \(result.exitStatus)."
                    : message
                return
            }

            try? await metricsPollingService.pollNow(server: server)
            await refreshContainer()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func containerStatusCommand(for containerName: String) -> String {
        let filter = "name=^/\(containerName)$"
        return "\(runtime.rawValue) ps -a --filter \(shellQuoted(filter)) --format '{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}'"
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

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

private enum ContainerAction {
    case start
    case stop
    case restart

    var title: String {
        switch self {
        case .start:
            return "Start"
        case .stop:
            return "Stop"
        case .restart:
            return "Restart"
        }
    }

    func command(for containerName: String, runtime: ContainerRuntimeKind) -> String {
        let runtimeCommand = runtime.rawValue
        let quotedName = shellQuoted(containerName)

        switch self {
        case .start:
            return "\(runtimeCommand) start \(quotedName)"
        case .stop:
            return "\(runtimeCommand) stop \(quotedName)"
        case .restart:
            return "\(runtimeCommand) restart \(quotedName)"
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
