//
//  ServerContainerListView.swift
//  Orbital
//
//  Created by Jonathan on 4/14/26.
//

import SwiftData
import SwiftUI

struct ServerContainerListView: View {
    let server: Server

    @Environment(MetricsPollingService.self) private var metricsPollingService
    @Query private var snapshots: [MetricSnapshot]

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
                        ForEach(sortedContainers, id: \.self) { container in
                            NavigationLink {
                                ServerContainerDetailView(
                                    server: server,
                                    runtime: latestSnapshot.containerRuntime,
                                    container: container
                                )
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(containerTint(for: container))
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 5)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(container.name)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(containerBadge(for: container))
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(containerTint(for: container))
                                        }

                                        Text(container.image)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        Text(container.status)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 2)
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

    private func containerTint(for container: ContainerStatusSnapshot) -> Color {
        if container.isUnhealthy { return .red }
        if container.isRestarting { return .orange }
        if container.isRunning { return .green }
        if container.isPaused { return .yellow }
        if container.isExited { return .secondary }
        return .blue
    }

    private func containerBadge(for container: ContainerStatusSnapshot) -> String {
        if let health = container.healthLabel {
            return health
        }
        return container.state.capitalized
    }
}
