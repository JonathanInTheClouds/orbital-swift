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
                    containerSummaryCard(for: latestSnapshot)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

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

    private func containerSummaryCard(for snapshot: MetricSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.indigo.opacity(0.16))
                        .frame(width: 56, height: 56)

                    Image(systemName: "shippingbox")
                        .font(.title3)
                        .foregroundStyle(.indigo)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Container Runtime")
                            .font(.headline.weight(.semibold))

                        Spacer(minLength: 8)

                        Text(snapshot.containerRuntime.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.indigo.opacity(0.12), in: Capsule())
                    }

                    Text(server.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(snapshot.containerRuntimeReachable ? "Runtime reachable" : "Runtime unavailable")
                        .font(.caption2)
                        .foregroundStyle(snapshot.containerRuntimeReachable ? .green : .secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                SummaryTile(label: "REACHABLE", value: snapshot.containerRuntimeReachable ? "Yes" : "No")
                SummaryTile(label: "RUNNING", value: "\(snapshot.runningContainerCount)")
                SummaryTile(label: "TOTAL", value: "\(snapshot.containerStatuses.count)")
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.indigo.opacity(0.18),
                            Color.indigo.opacity(0.06),
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
        }
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

private struct SummaryTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        }
    }
}
