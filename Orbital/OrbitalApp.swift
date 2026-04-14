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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Server.self,
            MetricSnapshot.self,
            Script.self,
            ScriptRun.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
