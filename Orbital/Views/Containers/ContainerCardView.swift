//
//  ContainerCardView.swift
//  Orbital
//
//  Created by Jonathan on 4/16/26.
//

import SwiftUI

// MARK: - Shared Helpers

enum ContainerCardStyle: String {
    case expanded
    case compact
}

func containerAccentColor(for container: ContainerStatusSnapshot) -> Color {
    if container.isUnhealthy  { return .red }
    if container.isRestarting { return .orange }
    if container.isRunning    { return .green }
    if container.isPaused     { return .yellow }
    return Color.secondary
}

// MARK: - Card View

struct ContainerCardView: View {
    let container: ContainerStatusSnapshot
    let serverName: String
    let runtime: ContainerRuntimeKind
    var style: ContainerCardStyle = .compact

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

    // MARK: - Expanded

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                iconBadge(size: 56, cornerRadius: 18, iconFont: .title3)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(container.name)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        statePill
                    }

                    Text("\(serverName) · \(runtime.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let health = container.healthLabel {
                            healthPill(health)
                        }

                        Text(container.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ContainerInfoTile(label: "IMAGE", value: imageShortName)
                ContainerInfoTile(label: "SERVER", value: serverName)
                ContainerInfoTile(label: "RUNTIME", value: runtime.displayName)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    // MARK: - Compact

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(container.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        statePill
                    }

                    Text("\(imageShortName) · \(serverName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Shared Components

    private var statePill: some View {
        Text(container.healthLabel ?? container.state.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(accentColor.opacity(0.12), in: Capsule())
    }

    private func healthPill(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(accentColor.opacity(0.12), in: Capsule())
    }

    private func iconBadge(size: CGFloat, cornerRadius: CGFloat, iconFont: Font) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(accentColor.opacity(0.16))
                .frame(width: size, height: size)

            Image(systemName: "shippingbox")
                .font(iconFont)
                .foregroundStyle(accentColor)
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
        containerAccentColor(for: container)
    }

    private var imageShortName: String {
        // Strip registry prefix and tag for display brevity
        let withoutTag = container.image.components(separatedBy: ":").first ?? container.image
        return withoutTag.components(separatedBy: "/").last ?? withoutTag
    }
}

// MARK: - Info Tile

private struct ContainerInfoTile: View {
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

// MARK: - Preview

#Preview("Expanded — Running") {
    ContainerCardView(
        container: ContainerStatusSnapshot(
            name: "api-server",
            image: "ghcr.io/myorg/api:latest",
            state: "running",
            status: "Up 3 days (healthy)"
        ),
        serverName: "prod-us-east",
        runtime: .docker,
        style: .expanded
    )
    .padding()
}

#Preview("Compact — Exited") {
    ContainerCardView(
        container: ContainerStatusSnapshot(
            name: "worker-cron",
            image: "myapp/worker:1.2.0",
            state: "exited",
            status: "Exited (1) 2 hours ago"
        ),
        serverName: "staging-01",
        runtime: .podman,
        style: .compact
    )
    .padding()
}
