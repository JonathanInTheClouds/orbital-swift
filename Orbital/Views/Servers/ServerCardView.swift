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

// MARK: - Card

struct ServerCardView: View {
    let server: Server
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 0) {
            // Color accent strip
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor)
                .frame(width: 5)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(server.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    StatusBadge(status: status)
                }

                HStack(spacing: 4) {
                    Image(systemName: "at")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(server.username)@\(server.host):\(server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !server.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(server.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var accentColor: Color {
        serverAccentColor(server.colorTag)
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
            server: Server(name: "prod-web-01", host: "192.168.1.100", port: 22, username: "admin",
                           tags: ["production", "web"]),
            status: .connected
        )
        ServerCardView(
            server: Server(name: "staging-db", host: "staging.example.com", port: 2222, username: "deploy",
                           tags: ["staging", "database"], colorTag: "orange"),
            status: .connecting
        )
        ServerCardView(
            server: Server(name: "home-lab", host: "192.168.0.50", port: 22, username: "pi",
                           colorTag: "purple"),
            status: .disconnected
        )
    }
    .padding()
}
