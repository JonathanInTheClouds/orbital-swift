//
//  SettingsView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(SSHService.self) private var sshService

    var body: some View {
        NavigationStack {
            List {
                Section("SSH") {
                    LabeledContent {
                        Text("libssh")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Engine", systemImage: "cpu")
                    }

                    LabeledContent {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(LibsshBridgeLoader.isNativeBridgeAvailable ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(LibsshBridgeLoader.isNativeBridgeAvailable ? "Ready" : "Pending")
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label("Status", systemImage: "dot.radiowaves.left.and.right")
                    }

                    LabeledContent {
                        Text("\(sshService.sessions.count)")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Active Sessions", systemImage: "terminal")
                    }

                    NavigationLink {
                        KnownHostsView()
                    } label: {
                        Label("Known Hosts", systemImage: "key.horizontal")
                    }
                }

                Section("Security") {
                    NavigationLink {
                        CredentialVaultView()
                    } label: {
                        Label("Credential Vault", systemImage: "lock.shield")
                    }

                    NavigationLink {
                        KeyManagementView()
                    } label: {
                        Label("SSH Keys", systemImage: "key")
                    }
                }

                Section("About") {
                    LabeledContent("Version") {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Build") {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
