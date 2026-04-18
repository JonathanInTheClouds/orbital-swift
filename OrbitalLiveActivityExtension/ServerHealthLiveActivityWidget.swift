//
//  ServerHealthLiveActivityWidget.swift
//  OrbitalLiveActivityExtension
//
//  Created by Jonathan on 4/17/26.
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
                    ExpandedHeader(context: context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedStatus(context: context)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedMetrics(context: context)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalStatusView(status: context.state.status)
            }
            .widgetURL(serverURL(for: context.attributes.serverID))
            .keylineTint(statusColor(for: context.state.status))
        }
    }

    private func serverURL(for serverID: String) -> URL {
        URL(string: "orbital://server/\(serverID)")!
    }
}

private struct CompactLeadingView: View {
    let context: ActivityViewContext<ServerHealthActivityAttributes>

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.22))
                Image(systemName: context.state.status.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 20, height: 20)

            Text(serverMonogram)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
    }

    private var serverMonogram: String {
        let words = context.attributes.serverName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)

        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? String(context.attributes.serverName.prefix(2)).uppercased() : letters.uppercased()
    }

    private var statusColor: Color {
        color(for: context.state.status)
    }
}

private struct CompactTrailingView: View {
    let context: ActivityViewContext<ServerHealthActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hottestMetric.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(percentString(hottestMetric.value))
                .font(.caption2.monospacedDigit().weight(.semibold))
        }
    }

    private var hottestMetric: (label: String, value: Double) {
        [
            ("CPU", context.state.cpuPercent),
            ("MEM", context.state.memoryPercent),
            ("DSK", context.state.diskPercent)
        ]
        .max { $0.1 < $1.1 } ?? ("CPU", context.state.cpuPercent)
    }
}

private struct MinimalStatusView: View {
    let status: ServerHealthActivityAttributes.Status

    var body: some View {
        ZStack {
            Circle()
                .fill(color(for: status).opacity(0.2))
            Circle()
                .strokeBorder(color(for: status).opacity(0.4), lineWidth: 1)
            Image(systemName: status.systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color(for: status))
        }
        .frame(width: 24, height: 24)
    }
}

private struct ExpandedHeader: View {
    let context: ActivityViewContext<ServerHealthActivityAttributes>

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(statusColor.opacity(0.16))
                Image(systemName: context.state.status.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.serverName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var summaryLine: String {
        if let runtime = context.state.containerRuntimeName {
            return "\(runtime) · \(context.state.runningContainers) running"
        }

        return "Telemetry active"
    }

    private var statusColor: Color {
        color(for: context.state.status)
    }
}

private struct ExpandedStatus: View {
    let context: ActivityViewContext<ServerHealthActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(context.state.status.title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.16), in: Capsule())

            Text(context.state.lastUpdatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 6)
    }

    private var statusColor: Color {
        color(for: context.state.status)
    }
}

private struct ExpandedMetrics: View {
    let context: ActivityViewContext<ServerHealthActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricTile(
                    title: "CPU",
                    value: context.state.cpuPercent,
                    tint: .orange
                )
                MetricTile(
                    title: "MEM",
                    value: context.state.memoryPercent,
                    tint: .blue
                )
                MetricTile(
                    title: "DISK",
                    value: context.state.diskPercent,
                    tint: .mint
                )
            }

            if let detailLine {
                HStack(spacing: 8) {
                    Image(systemName: detailIconName)
                        .foregroundStyle(statusColor)
                    Text(detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.leading)
                .padding(.top, -3)
            }
        }
        .padding(.top, -2)
    }

    private var detailLine: String? {
        guard let runtime = context.state.containerRuntimeName else { return "Tap to open server details" }

        if !context.state.containerRuntimeReachable {
            return "\(runtime) unreachable"
        }

        if context.state.unhealthyContainers > 0 {
            let noun = context.state.unhealthyContainers == 1 ? "container" : "containers"
            return "\(context.state.unhealthyContainers) unhealthy \(noun)"
        }

        return "\(runtime) healthy · \(context.state.runningContainers) running"
    }

    private var detailIconName: String {
        if context.state.unhealthyContainers > 0 {
            return "exclamationmark.triangle.fill"
        }

        if context.state.containerRuntimeName != nil {
            return "shippingbox.fill"
        }

        return "arrow.up.right"
    }

    private var statusColor: Color {
        color(for: context.state.status)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ServerHealthActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(statusColor.opacity(0.16))
                    Image(systemName: context.state.status.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.serverName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(context.state.status.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(statusColor)

                        Text(context.state.lastUpdatedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            HStack(spacing: 10) {
                MetricTile(title: "CPU", value: context.state.cpuPercent, tint: .orange)
                MetricTile(title: "MEM", value: context.state.memoryPercent, tint: .blue)
                MetricTile(title: "DISK", value: context.state.diskPercent, tint: .mint)
            }

            if let containerLine {
                HStack(spacing: 8) {
                    Image(systemName: containerIconName)
                        .foregroundStyle(statusColor)
                    Text(containerLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .activityBackgroundTint(Color.black.opacity(0.18))
        .activitySystemActionForegroundColor(.white)
    }

    private var containerLine: String? {
        guard let runtime = context.state.containerRuntimeName else { return "Server health from latest telemetry sample" }

        if !context.state.containerRuntimeReachable {
            return "\(runtime) unavailable"
        }

        if context.state.unhealthyContainers > 0 {
            let noun = context.state.unhealthyContainers == 1 ? "container" : "containers"
            return "\(context.state.unhealthyContainers) unhealthy \(noun)"
        }

        return "\(runtime) healthy with \(context.state.runningContainers) running"
    }

    private var containerIconName: String {
        context.state.unhealthyContainers > 0 ? "exclamationmark.triangle.fill" : "shippingbox.fill"
    }

    private var statusColor: Color {
        color(for: context.state.status)
    }
}

private struct MetricTile: View {
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)

                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(percentString(value))
                .font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private func statusColor(for status: ServerHealthActivityAttributes.Status) -> Color {
    color(for: status)
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

private func percentString(_ value: Double) -> String {
    "\(Int(value.rounded()))%"
}
