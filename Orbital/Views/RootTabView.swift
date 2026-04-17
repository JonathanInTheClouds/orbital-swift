//
//  RootTabView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selectedTab: Tab = .servers

    enum Tab {
        case servers, terminal, containers, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ServerListView()
                .tabItem {
                    Label("Servers", systemImage: "square.3.layers.3d")
                }
                .tag(Tab.servers)

            TerminalListView()
                .tabItem {
                    Label("Terminals", systemImage: "apple.terminal.on.rectangle")
                }
                .tag(Tab.terminal)

            ContainersView()
                .tabItem {
                    Label("Containers", systemImage: "shippingbox")
                }
                .tag(Tab.containers)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
        .accessibilityIdentifier("root.tabView")
        .environment(SSHService.shared)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Server.self,
        MetricSnapshot.self,
        Script.self,
        ScriptRun.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    RootTabView()
        .modelContainer(container)
        .environment(MetricsPollingService(modelContext: container.mainContext, sshService: .shared))
}
