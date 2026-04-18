//
//  ServerHealthLiveActivityWidget.swift
//  OrbitalLiveActivityExtension
//
//  Created by Codex on 4/17/26.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct ServerHealthLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ServerHealthActivityAttributes.self) { context in
            LockScreenView(context: context)
                .widgetURL(serverURL(for: context.attributes.serverID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.serverName, systemImage: context.state.status.systemImage)
                        .font(.headline)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(context.state.status.title)
                            .font(.subheadline.weight(.semibold))
                        freshnessText(for: context.state.lastUpdatedAt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            metricPill("CPU", value: context.state.cpuPercent)
                            metricPill("MEM", value: context.state.memoryPercent)
                            metricPill("DISK", value: context.state.diskPercent)
                        }

                        if let containerSummary = containerSummary(for: context.state) {
                            Text(containerSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.status.systemImage)
            } compactTrailing: {
                Text(primaryCompactMetric(for: context.state))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.state.status.systemImage)
            }
            .widgetURL(serverURL(for: context.attributes.serverID))
            .keylineTint(color(for: context.state.status))
        }
    }

    private func serverURL(for serverID: String) -> URL {
        URL(string: "orbital://server/\(serverID)")!
    }

    @ViewBuilder
    private func metricPill(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(percentString(value))
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func primaryCompactMetric(for state: ServerHealthActivityAttributes.ContentState) -> String {
        let metrics = [state.cpuPercent, state.memoryPercent, state.diskPercent]
        let maximum = metrics.max() ?? 0
        return percentString(maximum)
    }

    private func percentString(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func freshnessText(for date: Date) -> Text {
        Text(date, style: .relative)
    }

    private func containerSummary(for state: ServerHealthActivityAttributes.ContentState) -> String? {
        guard let containerRuntimeName = state.containerRuntimeName else { return nil }

        if !state.containerRuntimeReachable {
            return "\(containerRuntimeName) unavailable"
        }

        if state.unhealthyContainers > 0 {
            let noun = state.unhealthyContainers == 1 ? "container" : "containers"
            return "\(state.unhealthyContainers) unhealthy \(noun)"
        }

        return "\(containerRuntimeName) running \(state.runningContainers)"
    }

    private func color(for status: ServerHealthActivityAttributes.Status) -> Color {
        switch status {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .stale:
            return .gray
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ServerHealthActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.serverName)
                        .font(.headline)
                        .lineLimit(1)

                    Label(context.state.status.title, systemImage: context.state.status.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(color(for: context.state.status))
                }

                Spacer()

                Text(context.state.lastUpdatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                statColumn(title: "CPU", value: context.state.cpuPercent)
                statColumn(title: "MEM", value: context.state.memoryPercent)
                statColumn(title: "DISK", value: context.state.diskPercent)
            }

            if let containerText = containerSummary {
                Text(containerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .activityBackgroundTint(Color.black.opacity(0.14))
        .activitySystemActionForegroundColor(.white)
    }

    private var containerSummary: String? {
        guard let containerRuntimeName = context.state.containerRuntimeName else { return nil }

        if !context.state.containerRuntimeReachable {
            return "\(containerRuntimeName) unavailable"
        }

        if context.state.unhealthyContainers > 0 {
            let noun = context.state.unhealthyContainers == 1 ? "container" : "containers"
            return "\(context.state.unhealthyContainers) unhealthy \(noun)"
        }

        return "\(containerRuntimeName) running \(context.state.runningContainers)"
    }

    @ViewBuilder
    private func statColumn(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))%")
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for status: ServerHealthActivityAttributes.Status) -> Color {
        switch status {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .stale:
            return .gray
        }
    }
}
