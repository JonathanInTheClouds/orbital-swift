//
//  MetricSnapshot.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Foundation
import SwiftData

struct DiskUsage: Codable {
    var mountPoint: String
    var usedBytes: Int64
    var totalBytes: Int64

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

struct NetworkStat: Codable {
    var interface: String
    var bytesIn: Int64
    var bytesOut: Int64
}

enum ContainerRuntimeKind: String, Codable {
    case none
    case docker
    case podman

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .docker:
            return "Docker"
        case .podman:
            return "Podman"
        }
    }
}

enum ContainerListFilter: String, CaseIterable, Codable, Identifiable {
    case all
    case unhealthy
    case restarting
    case running
    case paused
    case exited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .unhealthy:
            return "Unhealthy"
        case .restarting:
            return "Restarting"
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .exited:
            return "Stopped"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .unhealthy:
            return "exclamationmark.triangle.fill"
        case .restarting:
            return "arrow.triangle.2.circlepath"
        case .running:
            return "play.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .exited:
            return "stop.circle.fill"
        }
    }
}

struct ContainerStatusSnapshot: Codable, Hashable {
    var name: String
    var image: String
    var state: String
    var status: String

    private var normalizedState: String {
        state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedStatus: String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isRunning: Bool {
        normalizedState == "running"
    }

    var isExited: Bool {
        normalizedState == "exited" || normalizedState == "dead" || normalizedState == "created"
    }

    var isPaused: Bool {
        normalizedState == "paused"
    }

    var isRestarting: Bool {
        normalizedState == "restarting"
    }

    var isUnhealthy: Bool {
        normalizedStatus.contains("unhealthy")
    }

    var healthLabel: String? {
        if normalizedStatus.contains("unhealthy") {
            return "Unhealthy"
        }
        if normalizedStatus.contains("healthy") {
            return "Healthy"
        }
        return nil
    }

    func matches(_ filter: ContainerListFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .unhealthy:
            return isUnhealthy
        case .restarting:
            return isRestarting
        case .running:
            return isRunning
        case .paused:
            return isPaused
        case .exited:
            return isExited
        }
    }
}

/// Periodic snapshot of system metrics for a server (Phase 2 — stored but not queried in Phase 1)
@Model
final class MetricSnapshot {
    var id: UUID
    var server: Server?
    var serverID: UUID?
    var recordedAt: Date
    var cpuPercent: Double
    var memUsedBytes: Int64
    var memTotalBytes: Int64
    var swapUsedBytes: Int64
    var swapTotalBytes: Int64
    var diskUsages: [DiskUsage]
    var networkStats: [NetworkStat]
    var containerRuntime: ContainerRuntimeKind
    var containerRuntimeReachable: Bool
    var containerStatuses: [ContainerStatusSnapshot]
    var loadAvg1m: Double
    var loadAvg5m: Double
    var loadAvg15m: Double
    var uptimeSeconds: Int64

    init(
        id: UUID = UUID(),
        server: Server? = nil,
        serverID: UUID? = nil,
        recordedAt: Date = Date(),
        cpuPercent: Double = 0,
        memUsedBytes: Int64 = 0,
        memTotalBytes: Int64 = 0,
        swapUsedBytes: Int64 = 0,
        swapTotalBytes: Int64 = 0,
        diskUsages: [DiskUsage] = [],
        networkStats: [NetworkStat] = [],
        containerRuntime: ContainerRuntimeKind = .none,
        containerRuntimeReachable: Bool = false,
        containerStatuses: [ContainerStatusSnapshot] = [],
        loadAvg1m: Double = 0,
        loadAvg5m: Double = 0,
        loadAvg15m: Double = 0,
        uptimeSeconds: Int64 = 0
    ) {
        self.id = id
        self.server = server
        self.serverID = serverID ?? server?.id
        self.recordedAt = recordedAt
        self.cpuPercent = cpuPercent
        self.memUsedBytes = memUsedBytes
        self.memTotalBytes = memTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.diskUsages = diskUsages
        self.networkStats = networkStats
        self.containerRuntime = containerRuntime
        self.containerRuntimeReachable = containerRuntimeReachable
        self.containerStatuses = containerStatuses
        self.loadAvg1m = loadAvg1m
        self.loadAvg5m = loadAvg5m
        self.loadAvg15m = loadAvg15m
        self.uptimeSeconds = uptimeSeconds
    }
}

extension MetricSnapshot {
    var memoryUsageFraction: Double {
        guard memTotalBytes > 0 else { return 0 }
        return Double(memUsedBytes) / Double(memTotalBytes)
    }

    var swapUsageFraction: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return Double(swapUsedBytes) / Double(swapTotalBytes)
    }

    var primaryDiskUsage: DiskUsage? {
        diskUsages.first(where: { $0.mountPoint == "/" }) ??
        diskUsages.max(by: { $0.totalBytes < $1.totalBytes })
    }

    var hasContainerRuntime: Bool {
        containerRuntime != .none
    }

    var runningContainerCount: Int {
        containerStatuses.filter(\.isRunning).count
    }

    var exitedContainerCount: Int {
        containerStatuses.filter(\.isExited).count
    }

    var pausedContainerCount: Int {
        containerStatuses.filter(\.isPaused).count
    }

    var restartingContainerCount: Int {
        containerStatuses.filter(\.isRestarting).count
    }

    var unhealthyContainerCount: Int {
        containerStatuses.filter(\.isUnhealthy).count
    }
}
