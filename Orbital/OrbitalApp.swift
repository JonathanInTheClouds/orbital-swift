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
        let schema = Schema([
            Server.self,
            MetricSnapshot.self,
            Script.self,
            ScriptRun.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.sharedModelContainer = container
            self.metricsPollingService = MetricsPollingService(
                modelContext: container.mainContext,
                sshService: .shared
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
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
