//
//  SettingsView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
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
