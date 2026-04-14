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
                    LabeledContent("Engine") {
                        Text(sshService.backendDisplayName)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("libssh") {
                        Text(LibsshBridgeLoader.isNativeBridgeAvailable ? "Ready" : "Pending")
                            .foregroundStyle(.secondary)
                    }

                    Text(SSHBackendKind.libssh.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .environment(SSHService.shared)
}
