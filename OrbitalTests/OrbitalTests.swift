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
}
