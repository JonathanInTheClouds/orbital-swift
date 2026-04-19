//
//  OrbitalTests.swift
//  OrbitalTests
//
//  Created by Jonathan on 4/13/26.
//

import Foundation
import XCTest
@testable import Orbital

@MainActor
final class OrbitalTests: XCTestCase {
    func testConnectionStatusPresentationMappings() {
        XCTAssertEqual(ConnectionStatus.disconnected.label, "Offline")
        XCTAssertEqual(ConnectionStatus.disconnected.systemImage, "circle.fill")
        XCTAssertEqual(ConnectionStatus.disconnected.colorName, "gray")

        XCTAssertEqual(ConnectionStatus.connecting.label, "Connecting")
        XCTAssertEqual(ConnectionStatus.connecting.systemImage, "circle.dotted")
        XCTAssertEqual(ConnectionStatus.connecting.colorName, "yellow")

        XCTAssertEqual(ConnectionStatus.connected.label, "Online")
        XCTAssertEqual(ConnectionStatus.connected.systemImage, "circle.fill")
        XCTAssertEqual(ConnectionStatus.connected.colorName, "green")

        XCTAssertEqual(ConnectionStatus.error("Host key mismatch").label, "Error: Host key mismatch")
        XCTAssertEqual(ConnectionStatus.error("Host key mismatch").systemImage, "exclamationmark.circle.fill")
        XCTAssertEqual(ConnectionStatus.error("Host key mismatch").colorName, "red")
    }

    func testCardStylePreferenceStoreReadReturnsEmptyDictionaryForInvalidJSON() {
        XCTAssertEqual(CardStylePreferenceStore.read(from: "not-json"), [:])
    }

    func testCardStylePreferenceStoreWriteRoundTripsPreferences() {
        let serialized = CardStylePreferenceStore.write([
            "server-a": "expanded",
            "server-b": "compact"
        ])

        XCTAssertFalse(serialized.isEmpty)
        XCTAssertEqual(
            CardStylePreferenceStore.read(from: serialized),
            [
                "server-a": "expanded",
                "server-b": "compact"
            ]
        )
    }

    func testCardStylePreferenceStoreWriteReturnsEmptyStringForEmptyPreferences() {
        XCTAssertEqual(CardStylePreferenceStore.write([:]), "")
    }

    func testParseMetricsPayloadParsesCompletePayload() throws {
        let payload = try MetricsPollingService.parseMetricsPayload(
            from: """
            CPU 17.25
            LOAD 0.31 0.28 0.22
            UPTIME 7200
            MEM 16000 4000 8000 1000
            DISK / 250 500
            DISK /data 900 1200
            NET en0 1234 5678
            NET docker0 90 45
            CONTAINER_RUNTIME|docker|1
            CONTAINER|web|nginx:latest|running|Up 5 minutes (healthy)
            CONTAINER|db|postgres:16|exited|Exited (1) 2 hours ago
            """
        )

        XCTAssertEqual(payload.cpuPercent, 17.25, accuracy: 0.001)
        XCTAssertEqual(payload.loadAvg1m, 0.31, accuracy: 0.001)
        XCTAssertEqual(payload.loadAvg5m, 0.28, accuracy: 0.001)
        XCTAssertEqual(payload.loadAvg15m, 0.22, accuracy: 0.001)
        XCTAssertEqual(payload.uptimeSeconds, 7200)
        XCTAssertEqual(payload.memTotalBytes, 16000)
        XCTAssertEqual(payload.memUsedBytes, 4000)
        XCTAssertEqual(payload.swapTotalBytes, 8000)
        XCTAssertEqual(payload.swapUsedBytes, 1000)
        XCTAssertEqual(payload.diskUsages.map(\.mountPoint), ["/", "/data"])
        XCTAssertEqual(payload.networkStats.map(\.interface), ["en0", "docker0"])
        XCTAssertEqual(payload.containerRuntime, .docker)
        XCTAssertTrue(payload.containerRuntimeReachable)
        XCTAssertEqual(payload.containerStatuses.count, 2)
        XCTAssertEqual(payload.containerStatuses[0].name, "web")
        XCTAssertEqual(payload.containerStatuses[0].healthLabel, "Healthy")
        XCTAssertTrue(payload.containerStatuses[0].isRunning)
        XCTAssertEqual(payload.containerStatuses[1].name, "db")
        XCTAssertTrue(payload.containerStatuses[1].isExited)
    }

    func testParseMetricsPayloadThrowsForInvalidCPULine() {
        XCTAssertThrowsError(try MetricsPollingService.parseMetricsPayload(from: "CPU nope")) { error in
            XCTAssertEqual(
                error.localizedDescription,
                MetricsPollingError.invalidPayload("Invalid CPU line: CPU nope").localizedDescription
            )
        }
    }

    func testMetricsCommandsRunInsidePOSIXShell() {
        XCTAssertTrue(MetricsPollingService.metricsCommand.hasPrefix("/bin/sh <<'EOF'"))
        XCTAssertTrue(MetricsPollingService.metricsCommand.hasSuffix("EOF"))
        XCTAssertTrue(MetricsPollingService.macosMetricsCommand.hasPrefix("/bin/sh <<'EOF'"))
        XCTAssertTrue(MetricsPollingService.macosMetricsCommand.hasSuffix("EOF"))
    }

    func testParseMetricsPayloadKeepsNormalizedMacOSRootDisk() throws {
        let payload = try MetricsPollingService.parseMetricsPayload(
            from: """
            CPU 9.5
            LOAD 0.10 0.20 0.30
            UPTIME 180
            MEM 1000 400 0 0
            DISK / 846824664448 976797816832
            """
        )

        XCTAssertEqual(payload.diskUsages.count, 1)
        XCTAssertEqual(payload.diskUsages[0].mountPoint, "/")
        XCTAssertEqual(payload.diskUsages[0].usedBytes, 846_824_664_448)
        XCTAssertEqual(payload.diskUsages[0].totalBytes, 976_797_816_832)
    }

    func testPrimaryDiskUsagePrefersMacOSDataVolumeInLegacySnapshots() throws {
        let snapshot = makeSnapshot(
            cpuPercent: 12,
            memUsedBytes: 3_000,
            memTotalBytes: 8_000,
            diskUsages: [
                DiskUsage(mountPoint: "/", usedBytes: 12_161_460_000, totalBytes: 976_797_816_000),
                DiskUsage(mountPoint: "/System/Volumes/Data", usedBytes: 846_824_664_000, totalBytes: 976_797_816_000)
            ],
            containerStatuses: []
        )

        let primaryDisk = try XCTUnwrap(snapshot.primaryDiskUsage)
        XCTAssertEqual(primaryDisk.mountPoint, "/System/Volumes/Data")
        XCTAssertGreaterThan(primaryDisk.usedPercent, 0.8)
    }

    func testLinuxMetricsFixturesParseAcrossDistros() throws {
        for fixtureName in ["ubuntu_metrics", "debian_metrics", "fedora_metrics", "alpine_metrics"] {
            let payload = try MetricsPollingService.parseMetricsPayload(from: fixture(named: fixtureName))

            XCTAssertGreaterThanOrEqual(payload.cpuPercent, 0, "fixture=\(fixtureName)")
            XCTAssertGreaterThan(payload.memTotalBytes, 0, "fixture=\(fixtureName)")
            XCTAssertFalse(payload.diskUsages.isEmpty, "fixture=\(fixtureName)")
            XCTAssertEqual(payload.diskUsages[0].mountPoint, "/", "fixture=\(fixtureName)")
            XCTAssertFalse(payload.networkStats.isEmpty, "fixture=\(fixtureName)")
            XCTAssertFalse(payload.containerStatuses.contains { $0.name.isEmpty }, "fixture=\(fixtureName)")
        }
    }

    func testParseMetricsPayloadAcceptsOverlayRootDiskForContainerTargets() throws {
        let payload = try MetricsPollingService.parseMetricsPayload(
            from: """
            CPU 5.0
            LOAD 0.01 0.02 0.03
            UPTIME 200
            MEM 1000 500 0 0
            DISK / 7221362688 106769133568
            NET eth0 100 200
            CONTAINER_RUNTIME|none|0
            """
        )

        let primaryDisk = try XCTUnwrap(payload.diskUsages.first)
        XCTAssertEqual(primaryDisk.mountPoint, "/")
        XCTAssertGreaterThan(primaryDisk.totalBytes, primaryDisk.usedBytes)
    }

    func testServerHealthLiveActivitySupportBuildsHealthyState() {
        let snapshot = makeSnapshot(
            cpuPercent: 22,
            memUsedBytes: 2_000,
            memTotalBytes: 8_000,
            diskUsages: [DiskUsage(mountPoint: "/", usedBytes: 200, totalBytes: 1_000)],
            containerStatuses: []
        )

        let state = ServerHealthLiveActivitySupport.makeState(from: snapshot)

        XCTAssertEqual(state.status, .healthy)
        XCTAssertEqual(state.cpuPercent, 22, accuracy: 0.001)
        XCTAssertEqual(state.memoryPercent, 25, accuracy: 0.001)
        XCTAssertEqual(state.diskPercent, 20, accuracy: 0.001)
    }

    func testServerHealthLiveActivitySupportBuildsCriticalStateForUnhealthyContainers() {
        let snapshot = makeSnapshot(
            cpuPercent: 35,
            memUsedBytes: 3_000,
            memTotalBytes: 8_000,
            diskUsages: [DiskUsage(mountPoint: "/", usedBytes: 250, totalBytes: 1_000)],
            containerRuntime: .docker,
            containerRuntimeReachable: true,
            containerStatuses: [
                ContainerStatusSnapshot(
                    name: "api",
                    image: "nginx",
                    state: "running",
                    status: "Up 5 minutes (unhealthy)"
                )
            ]
        )

        let state = ServerHealthLiveActivitySupport.makeState(from: snapshot)

        XCTAssertEqual(state.status, .critical)
        XCTAssertEqual(state.unhealthyContainers, 1)
        XCTAssertEqual(state.containerRuntimeName, "Docker")
    }

    func testServerHealthLiveActivitySupportBuildsStaleStateFromExistingState() {
        let baseState = ServerHealthActivityAttributes.ContentState(
            status: .warning,
            cpuPercent: 76,
            memoryPercent: 63,
            diskPercent: 55,
            runningContainers: 4,
            unhealthyContainers: 0,
            containerRuntimeName: "Docker",
            containerRuntimeReachable: true,
            lastUpdatedAt: Date(timeIntervalSince1970: 10)
        )

        let staleState = ServerHealthLiveActivitySupport.makeStaleState(
            from: baseState,
            at: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(staleState.status, .stale)
        XCTAssertEqual(staleState.cpuPercent, 76, accuracy: 0.001)
        XCTAssertEqual(staleState.lastUpdatedAt, Date(timeIntervalSince1970: 100))
    }

    func testArchiveIncompatibleStoreMovesDatabaseFilesToBackupDirectory() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("Orbital.store")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")

        try Data("store".utf8).write(to: storeURL)
        try Data("shm".utf8).write(to: shmURL)
        try Data("wal".utf8).write(to: walURL)

        try OrbitalApp.archiveIncompatibleStore(at: storeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path))

        let backups = try archivedFiles(in: tempDirectory)
        XCTAssertEqual(backups.count, 3)
        XCTAssertTrue(backups.contains(where: { $0.lastPathComponent.hasSuffix("Orbital.store") }))
        XCTAssertTrue(backups.contains(where: { $0.lastPathComponent.hasSuffix("Orbital.store-shm") }))
        XCTAssertTrue(backups.contains(where: { $0.lastPathComponent.hasSuffix("Orbital.store-wal") }))
        XCTAssertEqual(try Data(contentsOf: matchingArchivedFile(suffix: "Orbital.store", in: backups)), Data("store".utf8))
        XCTAssertEqual(try Data(contentsOf: matchingArchivedFile(suffix: "Orbital.store-shm", in: backups)), Data("shm".utf8))
        XCTAssertEqual(try Data(contentsOf: matchingArchivedFile(suffix: "Orbital.store-wal", in: backups)), Data("wal".utf8))
    }

    func testArchiveIncompatibleStoreSkipsMissingSidecarFiles() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("Orbital.store")
        try Data("store".utf8).write(to: storeURL)

        try OrbitalApp.archiveIncompatibleStore(at: storeURL)

        let backups = try archivedFiles(in: tempDirectory)
        XCTAssertEqual(backups.count, 1)
        XCTAssertTrue(backups[0].lastPathComponent.hasSuffix("Orbital.store"))
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func archivedFiles(in tempDirectory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: tempDirectory.appendingPathComponent("StoreBackups", isDirectory: true),
            includingPropertiesForKeys: nil
        )
    }

    private func matchingArchivedFile(suffix: String, in backups: [URL]) throws -> URL {
        try XCTUnwrap(backups.first(where: { $0.lastPathComponent.hasSuffix(suffix) }))
    }

    private func fixture(named name: String) throws -> String {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("\(name).txt")

        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private func makeSnapshot(
        cpuPercent: Double,
        memUsedBytes: Int64,
        memTotalBytes: Int64,
        diskUsages: [DiskUsage],
        containerRuntime: ContainerRuntimeKind = .none,
        containerRuntimeReachable: Bool = false,
        containerStatuses: [ContainerStatusSnapshot]
    ) -> MetricSnapshot {
        MetricSnapshot(
            recordedAt: Date(timeIntervalSince1970: 50),
            cpuPercent: cpuPercent,
            memUsedBytes: memUsedBytes,
            memTotalBytes: memTotalBytes,
            diskUsages: diskUsages,
            containerRuntime: containerRuntime,
            containerRuntimeReachable: containerRuntimeReachable,
            containerStatuses: containerStatuses
        )
    }
}
