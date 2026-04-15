//
//  KeyManagementView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Crypto
import SwiftUI

struct KeyManagementView: View {
    @State private var keys: [StoredKey] = []
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var showImport = false
    @State private var importedPEM = ""
    @State private var importKeyName = ""
    @State private var error: String?
    @State private var copiedKey: String?
    @State private var keyToDeploy: StoredKey?

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if keys.isEmpty {
                ContentUnavailableView(
                    "No SSH Keys",
                    systemImage: "key.slash",
                    description: Text("Generate a new key pair or import an existing private key.")
                )
            } else {
                ForEach(keys) { key in
                    KeyRow(key: key, copiedKey: $copiedKey, onDeploy: {
                        keyToDeploy = key
                    }) {
                        Task { await deleteKey(key) }
                    }
                }
            }
        }
        .navigationTitle("SSH Keys")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await generateKey() }
                    } label: {
                        Label("Generate ED25519 Key", systemImage: "wand.and.stars")
                    }

                    Button {
                        showImport = true
                    } label: {
                        Label("Import Private Key", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isGenerating)
            }
        }
        .sheet(isPresented: $showImport) {
            importSheet
        }
        .sheet(item: $keyToDeploy) { key in
            DeployKeyToServerSheet(key: key)
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task { await loadKeys() }
        .overlay {
            if isGenerating {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Generating key pair…")
                            .font(.subheadline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Import Sheet

    private var importSheet: some View {
        NavigationStack {
            Form {
                Section("Key Name") {
                    TextField("e.g. my-home-lab-key", text: $importKeyName)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }

                Section("Private Key (PEM / OpenSSH)") {
                    TextEditor(text: $importedPEM)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)

                    Button("Paste from Clipboard") {
                        if let text = UIPasteboard.general.string {
                            importedPEM = text
                        }
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImport = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task { await importKey() }
                    }
                    .disabled(importKeyName.isEmpty || importedPEM.isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadKeys() async {
        isLoading = true
        defer { isLoading = false }
        let allKeys = (try? await KeychainService.shared.allKeys()) ?? []
        keys = allKeys
            .filter { $0.hasPrefix("sshkey:") }
            .map { StoredKey(keychainKey: $0, name: String($0.dropFirst("sshkey:".count))) }
    }

    private func generateKey() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            // Generate an ED25519 key pair using CryptoKit
            let privateKey = Curve25519.Signing.PrivateKey()
            let name = "orbital-\(Int(Date().timeIntervalSince1970))"
            let keychainKey = "sshkey:\(name)"

            // Store only the 32-byte private key seed; public key is derived on demand
            try await KeychainService.shared.save(key: keychainKey, data: privateKey.rawRepresentation)
            await loadKeys()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importKey() async {
        let name = importKeyName.trimmingCharacters(in: .whitespaces)
        let pem = importedPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !pem.isEmpty else { return }

        do {
            guard let data = pem.data(using: .utf8) else {
                throw KeyImportError.encodingFailed
            }
            let keychainKey = "sshkey:\(name)"
            try await KeychainService.shared.save(key: keychainKey, data: data)
            showImport = false
            importKeyName = ""
            importedPEM = ""
            await loadKeys()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteKey(_ key: StoredKey) async {
        do {
            try await KeychainService.shared.delete(key: key.keychainKey)
            await loadKeys()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - StoredKey Model

struct StoredKey: Identifiable {
    let id = UUID()
    let keychainKey: String
    let name: String
}

// MARK: - Key Row

private struct KeyRow: View {
    let key: StoredKey
    @Binding var copiedKey: String?
    let onDeploy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(key.name)
                    .font(.headline)
                Text(key.keychainKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if copiedKey == key.keychainKey {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            Button {
                copyPublicKey()
            } label: {
                Label("Copy Public Key", systemImage: "doc.on.doc")
            }
            .tint(.accentColor)

            Button(action: onDeploy) {
                Label("Deploy to Server", systemImage: "square.and.arrow.up")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func copyPublicKey() {
        Task {
            guard let raw = await KeychainService.shared.loadIfPresent(key: key.keychainKey),
                  let keyString = sshPublicKeyString(fromRawEd25519Seed: raw)
            else { return }

            UIPasteboard.general.string = keyString

            await MainActor.run {
                withAnimation { copiedKey = key.keychainKey }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copiedKey = nil }
                }
            }
        }
    }
}

// MARK: - Errors

enum KeyImportError: LocalizedError {
    case encodingFailed

    var errorDescription: String? { "Failed to encode the private key data." }
}

#Preview {
    NavigationStack {
        KeyManagementView()
    }
}
