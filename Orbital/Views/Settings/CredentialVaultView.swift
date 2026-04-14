//
//  CredentialVaultView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI
internal import LocalAuthentication

struct CredentialVaultView: View {
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var keys: [String] = []
    @State private var isLoadingKeys = false
    @State private var keyToDelete: String?
    @State private var deleteError: String?

    var body: some View {
        Group {
            if isUnlocked {
                unlockedContent
            } else {
                lockedState
            }
        }
        .navigationTitle("Credential Vault")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Authentication Error", isPresented: Binding(
            get: { authError != nil },
            set: { if !$0 { authError = nil } }
        )) {
            Button("OK") { authError = nil }
        } message: {
            Text(authError ?? "")
        }
        .confirmationDialog(
            "Delete Credential",
            isPresented: Binding(get: { keyToDelete != nil }, set: { if !$0 { keyToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete \"\(keyToDelete ?? "")\"", role: .destructive) {
                if let key = keyToDelete { Task { await deleteKey(key) } }
            }
            Button("Cancel", role: .cancel) { keyToDelete = nil }
        } message: {
            Text("This credential will be permanently removed from the Keychain.")
        }
    }

    // MARK: - Locked State

    private var lockedState: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Credential Vault")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Authenticate to view stored credentials.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await authenticate() }
            } label: {
                Label(
                    "Unlock with \(biometricLabel)",
                    systemImage: biometricSystemImage
                )
                .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
        }
        .padding()
    }

    // MARK: - Unlocked Content

    private var unlockedContent: some View {
        List {
            if isLoadingKeys {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if keys.isEmpty {
                ContentUnavailableView(
                    "No Credentials Stored",
                    systemImage: "key.slash",
                    description: Text("Add servers with passwords or private keys to populate the vault.")
                )
            } else {
                Section("\(keys.count) item\(keys.count == 1 ? "" : "s")") {
                    ForEach(keys, id: \.self) { key in
                        HStack {
                            Image(systemName: iconForKey(key))
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            Text(key)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                keyToDelete = key
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await loadKeys() }
        .task { await loadKeys() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { isUnlocked = false }
                } label: {
                    Image(systemName: "lock")
                }
            }
        }
    }

    // MARK: - Helpers

    private var biometricLabel: String {
        switch BiometricService.shared.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "Biometrics"
        }
    }

    private var biometricSystemImage: String {
        switch BiometricService.shared.biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "lock.open"
        }
    }

    private func iconForKey(_ key: String) -> String {
        if key.hasPrefix("hostkey:") { return "lock.laptopcomputer" }
        if key.hasPrefix("sshkey:") { return "key" }
        return "lock"
    }

    private func authenticate() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let success = try await BiometricService.shared.authenticate(reason: "Unlock the Orbital Credential Vault")
            if success {
                withAnimation { isUnlocked = true }
            }
        } catch {
            authError = error.localizedDescription
        }
    }

    private func loadKeys() async {
        isLoadingKeys = true
        defer { isLoadingKeys = false }
        keys = (try? await KeychainService.shared.allKeys()) ?? []
    }

    private func deleteKey(_ key: String) async {
        do {
            try await KeychainService.shared.delete(key: key)
            await loadKeys()
        } catch {
            deleteError = error.localizedDescription
        }
        keyToDelete = nil
    }
}

#Preview {
    NavigationStack {
        CredentialVaultView()
    }
}
