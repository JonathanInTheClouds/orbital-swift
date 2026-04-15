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

    init() {
        let schema = Self.appSchema
        let storeURL = Self.storeURL()

        do {
            let container = try Self.makeContainer(schema: schema, storeURL: storeURL)
            self.sharedModelContainer = container
            self.metricsPollingService = Self.makeMetricsPollingService(container: container)
        } catch {
            do {
                try Self.archiveIncompatibleStore(at: storeURL)
                let container = try Self.makeContainer(schema: schema, storeURL: storeURL)
                self.sharedModelContainer = container
                self.metricsPollingService = Self.makeMetricsPollingService(container: container)
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

private extension OrbitalApp {
    static var appSchema: Schema {
        Schema([
            Server.self,
            MetricSnapshot.self,
            Script.self,
            ScriptRun.self,
        ])
    }

    static func makeMetricsPollingService(container: ModelContainer) -> MetricsPollingService {
        MetricsPollingService(
            modelContext: container.mainContext,
            sshService: .shared
        )
    }

    static func makeContainer(schema: Schema, storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "OrbitalStore",
            schema: schema,
            url: storeURL
        )
        return try ModelContainer(for: schema, configurations: [configuration])
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
}
