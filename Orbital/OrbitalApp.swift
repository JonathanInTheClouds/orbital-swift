//
//  OrbitalApp.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI
import SwiftData

@main
struct OrbitalApp: App {
    let sharedModelContainer: ModelContainer
    let metricsPollingService: MetricsPollingService
    let liveActivityCoordinator: ServerHealthLiveActivityCoordinator

    init() {
        let schema = Self.appSchema
        let storeURL = Self.isUITesting ? nil : Self.storeURL()
        let liveActivityCoordinator = ServerHealthLiveActivityCoordinator()

        do {
            let container = try Self.makeContainer(schema: schema, storeURL: storeURL)
            try? Self.cleanupMetricSnapshots(in: container.mainContext)
            if Self.isUITestingLab {
                try? Self.seedUITestLabServers(in: container.mainContext)
            }
            self.sharedModelContainer = container
            self.liveActivityCoordinator = liveActivityCoordinator
            self.metricsPollingService = Self.makeMetricsPollingService(
                container: container,
                liveActivityCoordinator: liveActivityCoordinator
            )
        } catch {
            guard let storeURL else {
                fatalError("Could not create ModelContainer: \(error)")
            }

            do {
                try Self.archiveIncompatibleStore(at: storeURL)
                let container = try Self.makeContainer(schema: schema, storeURL: storeURL)
                try? Self.cleanupMetricSnapshots(in: container.mainContext)
                if Self.isUITestingLab {
                    try? Self.seedUITestLabServers(in: container.mainContext)
                }
                self.sharedModelContainer = container
                self.liveActivityCoordinator = liveActivityCoordinator
                self.metricsPollingService = Self.makeMetricsPollingService(
                    container: container,
                    liveActivityCoordinator: liveActivityCoordinator
                )
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(metricsPollingService)
        }
        .modelContainer(sharedModelContainer)
    }
}

extension OrbitalApp {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    static var isUITestingLab: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-lab")
            || ProcessInfo.processInfo.environment["ORBITAL_UI_TEST_LAB"] == "1"
    }

    static var appSchema: Schema {
        Schema([
            Server.self,
            MetricSnapshot.self,
            Script.self,
            ScriptRun.self,
        ])
    }

    static func makeMetricsPollingService(
        container: ModelContainer,
        liveActivityCoordinator: ServerHealthLiveActivityCoordinator
    ) -> MetricsPollingService {
        MetricsPollingService(
            modelContext: container.mainContext,
            sshService: .shared,
            liveActivityCoordinator: liveActivityCoordinator
        )
    }

    static func makeContainer(schema: Schema, storeURL: URL?) throws -> ModelContainer {
        if let storeURL {
            let configuration = ModelConfiguration(
                "OrbitalStore",
                schema: schema,
                url: storeURL
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    static func storeURL() -> URL {
        let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = applicationSupportURL.appendingPathComponent("Orbital", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL.appendingPathComponent("Orbital.store")
    }

    static func archiveIncompatibleStore(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let backupDirectory = storeURL.deletingLastPathComponent().appendingPathComponent("StoreBackups", isDirectory: true)

        if !fileManager.fileExists(atPath: backupDirectory.path) {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let candidateURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
        ]

        for sourceURL in candidateURLs where fileManager.fileExists(atPath: sourceURL.path) {
            let archivedURL = backupDirectory.appendingPathComponent("\(timestamp)-\(sourceURL.lastPathComponent)")
            if fileManager.fileExists(atPath: archivedURL.path) {
                try fileManager.removeItem(at: archivedURL)
            }
            try fileManager.moveItem(at: sourceURL, to: archivedURL)
        }
    }

    static func cleanupMetricSnapshots(in modelContext: ModelContext) throws {
        let serverIDs = Set(try modelContext.fetch(FetchDescriptor<Server>()).map(\.id))
        let snapshots = try modelContext.fetch(FetchDescriptor<MetricSnapshot>())

        var deletedAny = false

        for snapshot in snapshots {
            guard let serverID = snapshot.serverID, serverIDs.contains(serverID) else {
                modelContext.delete(snapshot)
                deletedAny = true
                continue
            }
        }

        if deletedAny {
            try modelContext.save()
        }
    }

    static func seedUITestLabServers(in modelContext: ModelContext) throws {
        for server in try modelContext.fetch(FetchDescriptor<Server>()) {
            modelContext.delete(server)
        }

        for snapshot in try modelContext.fetch(FetchDescriptor<MetricSnapshot>()) {
            modelContext.delete(snapshot)
        }

        let servers = [
            Server(
                name: "Lab Ubuntu",
                host: "127.0.0.1",
                port: 2222,
                username: "orbital",
                authMethod: .password,
                credentialRef: "ui-test-password:orbital",
                tags: ["lab", "ubuntu"],
                notes: "Seeded live UI test target",
                colorTag: "orange"
            ),
            Server(
                name: "Lab Debian",
                host: "127.0.0.1",
                port: 2223,
                username: "orbital",
                authMethod: .password,
                credentialRef: "ui-test-password:orbital",
                tags: ["lab", "debian"],
                notes: "Seeded live UI test target",
                colorTag: "blue"
            ),
            Server(
                name: "Lab Fedora",
                host: "127.0.0.1",
                port: 2224,
                username: "orbital",
                authMethod: .password,
                credentialRef: "ui-test-password:orbital",
                tags: ["lab", "fedora"],
                notes: "Seeded live UI test target",
                colorTag: "red"
            ),
            Server(
                name: "Lab Alpine",
                host: "127.0.0.1",
                port: 2225,
                username: "orbital",
                authMethod: .password,
                credentialRef: "ui-test-password:orbital",
                tags: ["lab", "alpine"],
                notes: "Seeded live UI test target",
                colorTag: "green"
            )
        ]

        for server in servers {
            modelContext.insert(server)
        }

        try modelContext.save()
    }
}
