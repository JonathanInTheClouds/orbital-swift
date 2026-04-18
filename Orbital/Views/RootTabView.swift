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
    @State private var requestedServerID: UUID?

    enum Tab {
        case servers, terminal, containers, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ServerListView(requestedServerID: $requestedServerID)
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
        .onOpenURL { url in
            guard let serverID = Self.serverID(from: url) else { return }
            selectedTab = .servers
            requestedServerID = serverID
        }
    }

    private static func serverID(from url: URL) -> UUID? {
        guard url.scheme == "orbital",
              url.host == "server" else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard let rawValue = components.first else { return nil }
        return UUID(uuidString: rawValue)
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
        .environment(
            MetricsPollingService(
                modelContext: container.mainContext,
                sshService: .shared,
                liveActivityCoordinator: ServerHealthLiveActivityCoordinator()
            )
        )
}
