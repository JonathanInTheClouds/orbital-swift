//
//  ServerCardView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI

// MARK: - Shared Color Helper

func serverAccentColor(_ colorTag: String) -> Color {
    switch colorTag {
    case "red":    return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green":  return .green
    case "teal":   return .teal
    case "cyan":   return .cyan
    case "blue":   return .blue
    case "indigo": return .indigo
    case "purple": return .purple
    case "pink":   return .pink
    default:       return .accentColor
    }
}

enum ServerCardStyle: String {
    case expanded
    case compact
}

private let serverPresenceGracePeriod: TimeInterval = 120

func serverDisplayStatus(
    sessionStatus: ConnectionStatus,
    lastReachableAt: Date?,
    now: Date = .now
) -> ConnectionStatus {
    switch sessionStatus {
    case .connecting, .connected, .error:
        return sessionStatus
    case .disconnected:
        guard let lastReachableAt else { return .disconnected }
        return now.timeIntervalSince(lastReachableAt) <= serverPresenceGracePeriod ? .connected : .disconnected
    }
}

// MARK: - Card

struct ServerCardView: View {
    let server: Server
    let status: ConnectionStatus
    let latestSnapshot: MetricSnapshot?
    let isPolling: Bool
    let lastError: String?
    var style: ServerCardStyle = .compact

    var body: some View {
        Group {
            switch style {
            case .expanded:
                expandedCard
            case .compact:
                compactCard
            }
        }
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                iconBadge(size: 56, cornerRadius: 18, iconFont: .title3)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(server.name)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        StatusBadge(status: status)
                    }

                    Text("\(server.username)@\(server.host):\(server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        statusPill(
                            label: isPolling ? "Polling" : "Idle",
                            tint: isPolling ? .green : .gray
                        )

                        if let latestSnapshot {
                            statusPill(
                                label: latestSnapshot.recordedAt.formatted(.relative(presentation: .named)),
                                tint: .blue
                            )
                        }

                        if server.osKind != .unknown {
                            statusPill(label: server.osKind.displayName, tint: .secondary)
                        }
                    }
                }
            }

            if let latestSnapshot {
                LazyVGrid(columns: metricColumns, spacing: 10) {
                    CompactMetricTile(
                        label: "CPU",
                        value: percentString(latestSnapshot.cpuPercent / 100),
                        caption: "load \(formatLoad(latestSnapshot.loadAvg1m))",
                        tint: .orange,
                        icon: "cpu"
                    )

                    CompactMetricTile(
                        label: "Memory",
                        value: percentString(latestSnapshot.memoryUsageFraction),
                        caption: formatBytes(latestSnapshot.memUsedBytes),
                        tint: .cyan,
                        icon: "memorychip"
                    )

                    CompactMetricTile(
                        label: "Disk",
                        value: latestSnapshot.primaryDiskUsage.map { percentString($0.usedPercent) } ?? "0%",
                        caption: latestSnapshot.primaryDiskUsage?.mountPoint ?? "/",
                        tint: .green,
                        icon: "internaldrive"
                    )
                }

                HStack(spacing: 10) {
                    ServerCardSignal(
                        title: "Uptime",
                        value: formatDuration(latestSnapshot.uptimeSeconds),
                        tint: .indigo
                    )

                    ServerCardSignal(
                        title: "Load",
                        value: formatLoad(latestSnapshot.loadAvg5m),
                        tint: .orange
                    )

                    ServerCardSignal(
                        title: "Interfaces",
                        value: "\(latestSnapshot.networkStats.count)",
                        tint: .blue
                    )
                }
            } else {
                noMetricsState(font: .subheadline)
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
            }

            footerContent
        }
        .padding(18)
        .background(cardBackground)
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                iconBadge(size: 44, cornerRadius: 16, iconFont: .headline)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(server.name)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        StatusBadge(status: status)
                    }

                    Text(server.host)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        statusPill(
                            label: isPolling ? "Polling" : "Idle",
                            tint: isPolling ? .green : .gray
                        )

                        if let latestSnapshot {
                            statusPill(
                                label: latestSnapshot.recordedAt.formatted(.relative(presentation: .named)),
                                tint: .blue
                            )
                        }
                    }
                }
            }

            if let latestSnapshot {
                HStack(spacing: 8) {
                    CompactInlineMetric(
                        label: "CPU",
                        value: percentString(latestSnapshot.cpuPercent / 100),
                        tint: .orange
                    )

                    CompactInlineMetric(
                        label: "MEM",
                        value: percentString(latestSnapshot.memoryUsageFraction),
                        tint: .cyan
                    )

                    CompactInlineMetric(
                        label: "DISK",
                        value: latestSnapshot.primaryDiskUsage.map { percentString($0.usedPercent) } ?? "0%",
                        tint: .green
                    )

                    CompactInlineMetric(
                        label: "LOAD",
                        value: formatLoad(latestSnapshot.loadAvg1m),
                        tint: .indigo
                    )
                }
            } else {
                noMetricsState(font: .caption)
            }

            compactFooterContent
        }
        .padding(16)
        .background(cardBackground)
    }

    @ViewBuilder
    private var footerContent: some View {
        if let lastError, !lastError.isEmpty {
            errorState(lastError, lineLimit: 2)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.red.opacity(0.08))
                }
        } else if !server.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(server.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.06), in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var compactFooterContent: some View {
        if let lastError, !lastError.isEmpty {
            errorState(lastError, lineLimit: 1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if !server.tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(server.tags.prefix(3)), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
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

    private var cardBackground: some View {
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
    }

    private var accentColor: Color {
        serverAccentColor(server.colorTag)
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 10)]
    }

    private func iconBadge(size: CGFloat, cornerRadius: CGFloat, iconFont: Font) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(accentColor.opacity(0.16))
                .frame(width: size, height: size)

            Image(systemName: "server.rack")
                .font(iconFont)
                .foregroundStyle(accentColor)
        }
    }

    private func noMetricsState(font: Font) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(accentColor)
            Text(isPolling ? "Collecting first metrics snapshot" : "No metrics collected yet")
                .font(font)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorState(_ message: String, lineLimit: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
        }
    }

    private func statusPill(label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func percentString(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private func formatLoad(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatBytes(_ value: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: value)
    }

    private func formatDuration(_ seconds: Int64) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        formatter.isAdaptive = true
        return formatter
    }()
}

private struct CompactInlineMetric: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CompactMetricTile: View {
    let label: String
    let value: String
    let caption: String
    let tint: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.title3.weight(.bold))

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }
}

private struct ServerCardSignal: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 7, height: 7)
                .overlay {
                    if status == .connecting {
                        Circle()
                            .stroke(badgeColor.opacity(0.4), lineWidth: 2)
                            .scaleEffect(1.6)
                    }
                }
            Text(status.label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }

    private var badgeColor: Color {
        switch status {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .disconnected: return .gray
        case .error:        return .red
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ServerCardView(
            server: Server(name: "prod-web-01", host: "192.168.1.100", port: 22, username: "admin", tags: ["production", "web"], colorTag: "teal"),
            status: .connected,
            latestSnapshot: MetricSnapshot(
                cpuPercent: 37,
                memUsedBytes: 4_200_000_000,
                memTotalBytes: 8_589_934_592,
                diskUsages: [DiskUsage(mountPoint: "/", usedBytes: 52_000_000_000, totalBytes: 90_000_000_000)],
                networkStats: [NetworkStat(interface: "eth0", bytesIn: 1, bytesOut: 1)],
                loadAvg1m: 0.82,
                loadAvg5m: 0.71,
                loadAvg15m: 0.55,
                uptimeSeconds: 182_000
            ),
            isPolling: true,
            lastError: nil,
            style: .expanded
        )

        ServerCardView(
            server: Server(name: "staging-db", host: "staging.example.com", port: 2222, username: "deploy", tags: ["staging", "database", "postgres"], colorTag: "orange"),
            status: .error("Host unreachable"),
            latestSnapshot: nil,
            isPolling: true,
            lastError: "Remote metrics command exited with status 255.",
            style: .compact
        )
    }
    .padding()
}
