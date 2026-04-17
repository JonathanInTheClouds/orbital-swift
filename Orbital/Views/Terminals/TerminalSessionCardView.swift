//
//  TerminalSessionCardView.swift
//  Orbital
//
//  Created by Jonathan on 4/15/26.
//

import SwiftUI

// MARK: - Card Style

enum TerminalCardStyle: String {
    case expanded
    case compact
}

// MARK: - Terminal Session Card

struct TerminalSessionCardView: View {
    let session: SSHSession
    let status: ConnectionStatus
    let server: Server?
    let connectedAt: Date
    var style: TerminalCardStyle = .compact

    var body: some View {
        switch style {
        case .expanded: expandedCard
        case .compact:  compactCard
        }
    }

    // MARK: - Expanded

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack(alignment: .top, spacing: 14) {
                iconBadge(size: 56, cornerRadius: 18, iconFont: .title3)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.displayTitle)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        StatusBadge(status: status)
                    }

                    if let server {
                        Text("\(server.username)@\(server.host):\(server.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("SSH Session")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if case .connected = status {
                            livePill
                        }

                        TimelineView(.periodic(from: connectedAt, by: 60)) { ctx in
                            statusPill(
                                label: formatDuration(from: connectedAt, to: ctx.date),
                                tint: accentColor
                            )
                        }

                        if let server, server.osKind != .unknown {
                            statusPill(label: server.osKind.displayName, tint: .secondary)
                        }
                    }
                }
            }

            // Session info tiles
            HStack(spacing: 10) {
                SessionInfoTile(
                    label: "STATUS",
                    value: statusValue,
                    tint: statusTileColor
                )

                TimelineView(.periodic(from: connectedAt, by: 60)) { ctx in
                    SessionInfoTile(
                        label: "DURATION",
                        value: formatDuration(from: connectedAt, to: ctx.date),
                        tint: accentColor
                    )
                }

                SessionInfoTile(
                    label: "PORT",
                    value: server.map { "\($0.port)" } ?? "22",
                    tint: .indigo
                )
            }

            // Tags footer
            if let server, !server.tags.isEmpty {
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
        .padding(18)
        .background(cardBackground)
    }

    // MARK: - Compact

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(alignment: .top, spacing: 12) {
                iconBadge(size: 44, cornerRadius: 16, iconFont: .headline)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(session.displayTitle)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        StatusBadge(status: status)
                    }

                    Text(server?.host ?? "SSH Session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if case .connected = status {
                            livePill
                        }

                        TimelineView(.periodic(from: connectedAt, by: 60)) { ctx in
                            statusPill(
                                label: formatDuration(from: connectedAt, to: ctx.date),
                                tint: accentColor
                            )
                        }
                    }
                }
            }

            // Compact info row
            HStack(spacing: 8) {
                CompactTerminalMetric(label: "STATUS", value: statusValue, tint: statusTileColor)

                TimelineView(.periodic(from: connectedAt, by: 60)) { ctx in
                    CompactTerminalMetric(
                        label: "TIME",
                        value: formatDuration(from: connectedAt, to: ctx.date),
                        tint: accentColor
                    )
                }

                CompactTerminalMetric(
                    label: "PORT",
                    value: server.map { "\($0.port)" } ?? "22",
                    tint: .indigo
                )

                if let server {
                    CompactTerminalMetric(label: "USER", value: server.username, tint: .cyan)
                }
            }

            // Tags (compact — max 3)
            if let server, !server.tags.isEmpty {
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
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Helpers

    private var accentColor: Color {
        server.map { serverAccentColor($0.colorTag) } ?? .teal
    }

    private var statusValue: String {
        switch status {
        case .connected:    return "Active"
        case .connecting:   return "Connecting"
        case .disconnected: return "Offline"
        case .error:        return "Error"
        }
    }

    private var statusTileColor: Color {
        switch status {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .disconnected: return .gray
        case .error:        return .red
        }
    }

    private var livePill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 5, height: 5)
            Text("Live")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.green.opacity(0.12), in: Capsule())
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

    private func iconBadge(size: CGFloat, cornerRadius: CGFloat, iconFont: Font) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(accentColor.opacity(0.16))
                .frame(width: size, height: size)

            Image(systemName: "apple.terminal.on.rectangle")
                .font(iconFont)
                .foregroundStyle(accentColor)
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

    private func formatDuration(from start: Date, to end: Date) -> String {
        let seconds = Int(max(0, end.timeIntervalSince(start)))
        let hours   = seconds / 3_600
        let minutes = (seconds % 3_600) / 60

        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }
}

// MARK: - Session Info Tile (expanded)

private struct SessionInfoTile: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
        }
    }
}

// MARK: - Compact Terminal Metric

private struct CompactTerminalMetric: View {
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
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
