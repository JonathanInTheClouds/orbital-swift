//
//  ServerHealthLiveActivitySupport.swift
//  Orbital
//
//  Created by Jonathan on 4/17/26.
//

import Foundation

enum ServerHealthLiveActivitySupport {
    static let warningCPUPercent = 70.0
    static let criticalCPUPercent = 90.0
    static let warningMemoryPercent = 75.0
    static let criticalMemoryPercent = 90.0
    static let warningDiskPercent = 80.0
    static let criticalDiskPercent = 92.0

    static func makeState(from snapshot: MetricSnapshot) -> ServerHealthActivityAttributes.ContentState {
        let cpuPercent = clamp(snapshot.cpuPercent)
        let memoryPercent = clamp(snapshot.memoryUsageFraction * 100)
        let diskPercent = clamp((snapshot.primaryDiskUsage?.usedPercent ?? 0) * 100)
        let unhealthyContainers = snapshot.unhealthyContainerCount
        let hasContainerIssue = snapshot.hasContainerRuntime && (!snapshot.containerRuntimeReachable || unhealthyContainers > 0)

        let status: ServerHealthActivityAttributes.Status
        if cpuPercent >= criticalCPUPercent
            || memoryPercent >= criticalMemoryPercent
            || diskPercent >= criticalDiskPercent
            || unhealthyContainers > 0 {
            status = .critical
        } else if cpuPercent >= warningCPUPercent
            || memoryPercent >= warningMemoryPercent
            || diskPercent >= warningDiskPercent
            || hasContainerIssue {
            status = .warning
        } else {
            status = .healthy
        }

        return ServerHealthActivityAttributes.ContentState(
            status: status,
            cpuPercent: cpuPercent,
            memoryPercent: memoryPercent,
            diskPercent: diskPercent,
            runningContainers: snapshot.runningContainerCount,
            unhealthyContainers: unhealthyContainers,
            containerRuntimeName: snapshot.hasContainerRuntime ? snapshot.containerRuntime.displayName : nil,
            containerRuntimeReachable: snapshot.containerRuntimeReachable,
            lastUpdatedAt: snapshot.recordedAt
        )
    }

    static func makeStaleState(from state: ServerHealthActivityAttributes.ContentState, at date: Date) -> ServerHealthActivityAttributes.ContentState {
        ServerHealthActivityAttributes.ContentState(
            status: .stale,
            cpuPercent: state.cpuPercent,
            memoryPercent: state.memoryPercent,
            diskPercent: state.diskPercent,
            runningContainers: state.runningContainers,
            unhealthyContainers: state.unhealthyContainers,
            containerRuntimeName: state.containerRuntimeName,
            containerRuntimeReachable: state.containerRuntimeReachable,
            lastUpdatedAt: date
        )
    }

    static func staleTimeout(for pollingInterval: TimeInterval) -> TimeInterval {
        max(45, pollingInterval * 2.5)
    }

    static func staleDismissDelay(for pollingInterval: TimeInterval) -> TimeInterval {
        max(20, min(60, pollingInterval * 1.5))
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}
