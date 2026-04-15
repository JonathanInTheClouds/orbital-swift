//
//  MetricsPollingService.swift
//  Orbital
//
//  Created by Jonathan on 4/14/26.
//

import Foundation
import OSLog
import SwiftData

private let metricsLog = Logger(subsystem: "com.orbital", category: "MetricsPolling")

@MainActor
@Observable
final class MetricsPollingService {
    static let defaultPollingInterval: TimeInterval = 30

    private let sshService: SSHService
    private let modelContext: ModelContext

    private var pollTasks: [UUID: Task<Void, Never>] = [:]
    private var pollingIntervals: [UUID: TimeInterval] = [:]
    private var lastRecordedAt: [UUID: Date] = [:]
    private var lastErrors: [UUID: String] = [:]
    private var manuallyStoppedServerIDs: Set<UUID> = []

    init(
        modelContext: ModelContext,
        sshService: SSHService
    ) {
        self.modelContext = modelContext
        self.sshService = sshService
    }

    func isPolling(serverID: UUID) -> Bool {
        pollTasks[serverID] != nil
    }

    func interval(for serverID: UUID) -> TimeInterval? {
        pollingIntervals[serverID]
    }

    func lastRecordedAt(for serverID: UUID) -> Date? {
        lastRecordedAt[serverID]
    }

    func lastError(for serverID: UUID) -> String? {
        lastErrors[serverID]
    }

    func startPolling(
        server: Server,
        every interval: TimeInterval
    ) {
        stopPolling(serverID: server.id, isManual: false)

        let sanitizedInterval = max(interval, 5)
        pollingIntervals[server.id] = sanitizedInterval
        lastErrors[server.id] = nil
        manuallyStoppedServerIDs.remove(server.id)

        pollTasks[server.id] = Task { [weak self, server] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await self.collectMetrics(for: server)
                    self.lastErrors[server.id] = nil
                } catch {
                    let message = error.localizedDescription
                    self.lastErrors[server.id] = message
                    metricsLog.error("[\(server.name)] Metrics poll failed: \(message, privacy: .public)")
                }

                do {
                    try await Task.sleep(for: .seconds(sanitizedInterval))
                } catch {
                    return
                }
            }
        }
    }

    func stopPolling(serverID: UUID) {
        stopPolling(serverID: serverID, isManual: true)
    }

    func ensureAutomaticPolling(for servers: [Server]) {
        let activeServerIDs = Set(servers.map(\.id))

        for serverID in Array(pollTasks.keys) where !activeServerIDs.contains(serverID) {
            stopPolling(serverID: serverID, isManual: false)
        }

        for server in servers where !isPolling(serverID: server.id) && !manuallyStoppedServerIDs.contains(server.id) {
            startPolling(server: server, every: pollingIntervals[server.id] ?? Self.defaultPollingInterval)
        }
    }

    private func stopPolling(serverID: UUID, isManual: Bool) {
        pollTasks[serverID]?.cancel()
        pollTasks.removeValue(forKey: serverID)

        if isManual {
            manuallyStoppedServerIDs.insert(serverID)
        } else {
            manuallyStoppedServerIDs.remove(serverID)
        }

        Task {
            await sshService.disconnectCommandTransport(serverID: serverID)
        }
    }

    func pollNow(server: Server) async throws {
        try await collectMetrics(for: server)
        lastErrors[server.id] = nil
    }

    private func collectMetrics(for server: Server) async throws {
        let result = try await sshService.runCommand(Self.metricsCommand, on: server)

        guard result.exitStatus == 0 else {
            let message = result.standardErrorString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MetricsPollingError.commandFailed(
                message.isEmpty ? "Remote metrics command exited with status \(result.exitStatus)." : message
            )
        }

        let payload = try Self.parseMetricsPayload(from: result.standardOutputString)
        let snapshot = MetricSnapshot(
            server: server,
            recordedAt: Date(),
            cpuPercent: payload.cpuPercent,
            memUsedBytes: payload.memUsedBytes,
            memTotalBytes: payload.memTotalBytes,
            swapUsedBytes: payload.swapUsedBytes,
            swapTotalBytes: payload.swapTotalBytes,
            diskUsages: payload.diskUsages,
            networkStats: payload.networkStats,
            containerRuntime: payload.containerRuntime,
            containerRuntimeReachable: payload.containerRuntimeReachable,
            containerStatuses: payload.containerStatuses,
            loadAvg1m: payload.loadAvg1m,
            loadAvg5m: payload.loadAvg5m,
            loadAvg15m: payload.loadAvg15m,
            uptimeSeconds: payload.uptimeSeconds
        )

        modelContext.insert(snapshot)
        server.lastSeenAt = snapshot.recordedAt
        lastRecordedAt[server.id] = snapshot.recordedAt

        do {
            try modelContext.save()
        } catch {
            throw MetricsPollingError.persistenceFailed(error.localizedDescription)
        }
    }
}

private extension MetricsPollingService {
    struct ParsedMetricsPayload {
        var cpuPercent: Double = 0
        var memUsedBytes: Int64 = 0
        var memTotalBytes: Int64 = 0
        var swapUsedBytes: Int64 = 0
        var swapTotalBytes: Int64 = 0
        var diskUsages: [DiskUsage] = []
        var networkStats: [NetworkStat] = []
        var containerRuntime: ContainerRuntimeKind = .none
        var containerRuntimeReachable: Bool = false
        var containerStatuses: [ContainerStatusSnapshot] = []
        var loadAvg1m: Double = 0
        var loadAvg5m: Double = 0
        var loadAvg15m: Double = 0
        var uptimeSeconds: Int64 = 0
    }

    static let metricsCommand = """
    cpu_sample() {
        awk '/^cpu / { idle=$5+$6; total=0; for (i=2; i<=NF; i++) total+=$i; print total, idle }' /proc/stat
    }

    set -- $(cpu_sample)
    cpu_total_1=$1
    cpu_idle_1=$2
    sleep 0.25
    set -- $(cpu_sample)
    cpu_total_2=$1
    cpu_idle_2=$2

    cpu_percent=$(awk -v total="$((cpu_total_2 - cpu_total_1))" -v idle="$((cpu_idle_2 - cpu_idle_1))" 'BEGIN { if (total <= 0) print "0.00"; else printf "%.2f", ((total - idle) / total) * 100 }')
    echo "CPU $cpu_percent"

    read -r load1 load5 load15 _ < /proc/loadavg
    echo "LOAD $load1 $load5 $load15"

    read -r uptime_seconds _ < /proc/uptime
    uptime_seconds=${uptime_seconds%.*}
    echo "UPTIME $uptime_seconds"

    awk '
    /^MemTotal:/ { mem_total=$2 * 1024 }
    /^MemAvailable:/ { mem_available=$2 * 1024 }
    /^SwapTotal:/ { swap_total=$2 * 1024 }
    /^SwapFree:/ { swap_free=$2 * 1024 }
    END {
        mem_used=mem_total - mem_available
        if (mem_used < 0) mem_used = 0
        swap_used=swap_total - swap_free
        if (swap_used < 0) swap_used = 0
        printf "MEM %.0f %.0f %.0f %.0f\\n", mem_total, mem_used, swap_total, swap_used
    }' /proc/meminfo

    df -kPT | while IFS= read -r line; do
        set -- $line
        [ "$1" = "Filesystem" ] && continue
        fstype=$2
        mountpoint=$7
        [ -n "$mountpoint" ] || continue
        case "$fstype" in
            tmpfs|devtmpfs|proc|sysfs|cgroup|cgroup2|mqueue|devpts|tracefs|debugfs|pstore|securityfs|configfs|overlay|squashfs|ramfs|autofs|fusectl|binfmt_misc|nsfs|hugetlbfs|rpc_pipefs|nfsd|bpf)
                continue
                ;;
        esac
        case "$mountpoint" in
            /run|/run/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*)
                continue
                ;;
        esac
        echo "DISK $mountpoint $(( $4 * 1024 )) $(( $3 * 1024 ))"
    done

    while IFS=: read -r iface stats; do
        [ -n "$stats" ] || continue
        iface=$(printf "%s" "$iface" | awk '{$1=$1; print}')
        [ -n "$iface" ] || continue
        case "$iface" in
            Inter-*|face) continue ;;
        esac
        set -- $stats
        echo "NET $iface $1 $9"
    done < /proc/net/dev

    container_runtime=none
    container_reachable=0

    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            container_runtime=docker
            container_reachable=1
        else
            container_runtime=docker
        fi
    fi

    if [ "$container_reachable" -eq 0 ] && command -v podman >/dev/null 2>&1; then
        if podman info >/dev/null 2>&1; then
            container_runtime=podman
            container_reachable=1
        elif [ "$container_runtime" = "none" ]; then
            container_runtime=podman
        fi
    fi

    echo "CONTAINER_RUNTIME|$container_runtime|$container_reachable"

    if [ "$container_reachable" -eq 1 ]; then
        "$container_runtime" ps -a --format '{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}' | while IFS= read -r container_line; do
            [ -n "$container_line" ] || continue
            echo "CONTAINER|$container_line"
        done
    fi
    """

    static func parseMetricsPayload(from output: String) throws -> ParsedMetricsPayload {
        var payload = ParsedMetricsPayload()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("CONTAINER_RUNTIME|") {
                let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count >= 3 else {
                    throw MetricsPollingError.invalidPayload("Invalid container runtime line: \(line)")
                }

                payload.containerRuntime = ContainerRuntimeKind(rawValue: String(parts[1])) ?? .none
                payload.containerRuntimeReachable = parts[2] == "1"
                continue
            }

            if line.hasPrefix("CONTAINER|") {
                let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
                guard parts.count >= 5 else {
                    throw MetricsPollingError.invalidPayload("Invalid container line: \(line)")
                }

                payload.containerStatuses.append(
                    ContainerStatusSnapshot(
                        name: String(parts[1]),
                        image: String(parts[2]),
                        state: String(parts[3]),
                        status: String(parts[4])
                    )
                )
                continue
            }

            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let prefix = components.first else { continue }

            switch prefix {
            case "CPU":
                guard components.count >= 2, let value = Double(components[1]) else {
                    throw MetricsPollingError.invalidPayload("Invalid CPU line: \(line)")
                }
                payload.cpuPercent = value

            case "LOAD":
                guard components.count >= 4,
                      let load1 = Double(components[1]),
                      let load5 = Double(components[2]),
                      let load15 = Double(components[3]) else {
                    throw MetricsPollingError.invalidPayload("Invalid load line: \(line)")
                }
                payload.loadAvg1m = load1
                payload.loadAvg5m = load5
                payload.loadAvg15m = load15

            case "UPTIME":
                guard components.count >= 2, let value = Int64(components[1]) else {
                    throw MetricsPollingError.invalidPayload("Invalid uptime line: \(line)")
                }
                payload.uptimeSeconds = value

            case "MEM":
                guard components.count >= 5,
                      let memTotal = Int64(components[1]),
                      let memUsed = Int64(components[2]),
                      let swapTotal = Int64(components[3]),
                      let swapUsed = Int64(components[4]) else {
                    throw MetricsPollingError.invalidPayload("Invalid memory line: \(line)")
                }
                payload.memTotalBytes = memTotal
                payload.memUsedBytes = memUsed
                payload.swapTotalBytes = swapTotal
                payload.swapUsedBytes = swapUsed

            case "DISK":
                guard components.count >= 4,
                      let used = Int64(components[2]),
                      let total = Int64(components[3]) else {
                    throw MetricsPollingError.invalidPayload("Invalid disk line: \(line)")
                }
                payload.diskUsages.append(
                    DiskUsage(
                        mountPoint: String(components[1]),
                        usedBytes: used,
                        totalBytes: total
                    )
                )

            case "NET":
                guard components.count >= 4,
                      let bytesIn = Int64(components[2]),
                      let bytesOut = Int64(components[3]) else {
                    throw MetricsPollingError.invalidPayload("Invalid network line: \(line)")
                }
                payload.networkStats.append(
                    NetworkStat(
                        interface: String(components[1]),
                        bytesIn: bytesIn,
                        bytesOut: bytesOut
                    )
                )

            default:
                continue
            }
        }

        return payload
    }
}

enum MetricsPollingError: LocalizedError {
    case commandFailed(String)
    case invalidPayload(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .invalidPayload(let message):
            return message
        case .persistenceFailed(let message):
            return "Failed to save the metrics snapshot: \(message)"
        }
    }
}
