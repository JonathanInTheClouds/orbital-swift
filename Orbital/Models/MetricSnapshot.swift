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

/// Periodic snapshot of system metrics for a server (Phase 2 — stored but not queried in Phase 1)
@Model
final class MetricSnapshot {
    var id: UUID
    var server: Server?
    var recordedAt: Date
    var cpuPercent: Double
    var memUsedBytes: Int64
    var memTotalBytes: Int64
    var swapUsedBytes: Int64
    var swapTotalBytes: Int64
    var diskUsages: [DiskUsage]
    var networkStats: [NetworkStat]
    var loadAvg1m: Double
    var loadAvg5m: Double
    var loadAvg15m: Double
    var uptimeSeconds: Int64

    init(
        id: UUID = UUID(),
        server: Server? = nil,
        recordedAt: Date = Date(),
        cpuPercent: Double = 0,
        memUsedBytes: Int64 = 0,
        memTotalBytes: Int64 = 0,
        swapUsedBytes: Int64 = 0,
        swapTotalBytes: Int64 = 0,
        diskUsages: [DiskUsage] = [],
        networkStats: [NetworkStat] = [],
        loadAvg1m: Double = 0,
        loadAvg5m: Double = 0,
        loadAvg15m: Double = 0,
        uptimeSeconds: Int64 = 0
    ) {
        self.id = id
        self.server = server
        self.recordedAt = recordedAt
        self.cpuPercent = cpuPercent
        self.memUsedBytes = memUsedBytes
        self.memTotalBytes = memTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.diskUsages = diskUsages
        self.networkStats = networkStats
        self.loadAvg1m = loadAvg1m
        self.loadAvg5m = loadAvg5m
        self.loadAvg15m = loadAvg15m
        self.uptimeSeconds = uptimeSeconds
    }
}
