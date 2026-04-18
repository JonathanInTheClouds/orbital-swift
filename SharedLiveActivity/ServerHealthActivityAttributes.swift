//
//  ServerHealthActivityAttributes.swift
//  Orbital
//
//  Created by Codex on 4/17/26.
//

import ActivityKit
import Foundation

struct ServerHealthActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: Status
        var cpuPercent: Double
        var memoryPercent: Double
        var diskPercent: Double
        var runningContainers: Int
        var unhealthyContainers: Int
        var containerRuntimeName: String?
        var containerRuntimeReachable: Bool
        var lastUpdatedAt: Date

        init(
            status: Status,
            cpuPercent: Double,
            memoryPercent: Double,
            diskPercent: Double,
            runningContainers: Int,
            unhealthyContainers: Int,
            containerRuntimeName: String?,
            containerRuntimeReachable: Bool,
            lastUpdatedAt: Date
        ) {
            self.status = status
            self.cpuPercent = cpuPercent
            self.memoryPercent = memoryPercent
            self.diskPercent = diskPercent
            self.runningContainers = runningContainers
            self.unhealthyContainers = unhealthyContainers
            self.containerRuntimeName = containerRuntimeName
            self.containerRuntimeReachable = containerRuntimeReachable
            self.lastUpdatedAt = lastUpdatedAt
        }
    }

    enum Status: String, Codable, Hashable {
        case healthy
        case warning
        case critical
        case stale

        var title: String {
            switch self {
            case .healthy:
                return "Healthy"
            case .warning:
                return "Warning"
            case .critical:
                return "Critical"
            case .stale:
                return "Stale"
            }
        }

        var systemImage: String {
            switch self {
            case .healthy:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .critical:
                return "xmark.octagon.fill"
            case .stale:
                return "clock.badge.exclamationmark.fill"
            }
        }
    }

    var serverID: String
    var serverName: String

    init(serverID: UUID, serverName: String) {
        self.serverID = serverID.uuidString
        self.serverName = serverName
    }
}
