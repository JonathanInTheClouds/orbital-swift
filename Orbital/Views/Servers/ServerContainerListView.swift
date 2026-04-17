//
//  ServerContainerListView.swift
//  Orbital
//
//  Created by Codex on 4/14/26.
//

import SwiftData
import SwiftUI

struct ServerContainerListView: View {
    let server: Server

    @Environment(MetricsPollingService.self) private var metricsPollingService
    @Query private var snapshots: [MetricSnapshot]

    @AppStorage("containerCardStyleByEntryID") private var cardStyleStorage = ""

    init(server: Server) {
        self.server = server

        let serverID = server.id
        _snapshots = Query(
            filter: #Predicate<MetricSnapshot> { snapshot in
                snapshot.server?.id == serverID
            },
            sort: [SortDescriptor(\MetricSnapshot.recordedAt, order: .reverse)]
        )
    }

    var body: some View {
        List {
            if let latestSnapshot {
                Section {
                    LabeledContent("Runtime", value: latestSnapshot.containerRuntime.displayName)
                    LabeledContent("Reachable", value: latestSnapshot.containerRuntimeReachable ? "Yes" : "No")
                    LabeledContent("Running", value: "\(latestSnapshot.runningContainerCount)")
                    LabeledContent("Total", value: "\(latestSnapshot.containerStatuses.count)")
                }

                if latestSnapshot.containerStatuses.isEmpty {
                    Section {
                        Text("No containers detected on this server.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Containers") {
                        ForEach(sortedContainers, id: \.name) { container in
                            NavigationLink {
                                ContainerDetailView(
                                    server: server,
                                    runtime: latestSnapshot.containerRuntime,
                                    containerName: container.name,
                                    initialContainer: container
                                )
                            } label: {
                                ContainerCardView(
                                    container: container,
                                    serverName: server.name,
                                    runtime: latestSnapshot.containerRuntime,
                                    style: cardStyle(for: container)
                                )
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    toggleCardStyle(for: container)
                                } label: {
                                    Label(
                                        cardStyle(for: container) == .expanded ? "Condense" : "Detail",
                                        systemImage: cardStyle(for: container) == .expanded
                                            ? "rectangle.compress.vertical"
                                            : "rectangle.grid.1x2"
                                    )
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("No container metrics yet. Run a poll to populate this screen.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Containers")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            try? await metricsPollingService.pollNow(server: server)
        }
    }

    private var latestSnapshot: MetricSnapshot? {
        snapshots.first
    }

    private var sortedContainers: [ContainerStatusSnapshot] {
        guard let latestSnapshot else { return [] }

        return latestSnapshot.containerStatuses.sorted { lhs, rhs in
            let lhsPriority = containerPriority(for: lhs)
            let rhsPriority = containerPriority(for: rhs)

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func containerPriority(for container: ContainerStatusSnapshot) -> Int {
        if container.isUnhealthy { return 0 }
        if container.isRestarting { return 1 }
        if container.isRunning { return 2 }
        if container.isPaused { return 3 }
        if container.isExited { return 4 }
        return 5
    }

    // MARK: - Card Style

    private func entryID(for container: ContainerStatusSnapshot) -> String {
        "\(server.id.uuidString)_\(container.name)"
    }

    private var cardStylesByEntryID: [String: String] {
        CardStylePreferenceStore.read(from: cardStyleStorage)
    }

    private func cardStyle(for container: ContainerStatusSnapshot) -> ContainerCardStyle {
        let key = entryID(for: container)
        guard let raw = cardStylesByEntryID[key],
              let style = ContainerCardStyle(rawValue: raw) else { return .compact }
        return style
    }

    private func toggleCardStyle(for container: ContainerStatusSnapshot) {
        let key = entryID(for: container)
        let next: ContainerCardStyle = cardStyle(for: container) == .expanded ? .compact : .expanded
        var styles = cardStylesByEntryID
        styles[key] = next.rawValue
        cardStyleStorage = CardStylePreferenceStore.write(styles)
    }
}
