//
//  KnownHostsView.swift
//  Orbital
//
//  Created by Jonathan on 4/16/26.
//

import SwiftUI

struct KnownHostEntry: Identifiable {
    let id = UUID()
    let keychainKey: String
    let hostname: String
    let fingerprint: String
}

struct KnownHostsView: View {
    @State private var entries: [KnownHostEntry] = []
    @State private var isLoading = false
    @State private var entryToDelete: KnownHostEntry?
    @State private var confirmClearAll = false
    @State private var error: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Known Hosts",
                    systemImage: "key.horizontal.slash",
                    description: Text("Host key fingerprints are cached here the first time you connect to a server.")
                )
            } else {
                Section {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.laptopcomputer")
                                    .foregroundStyle(.tint)
                                    .frame(width: 20)
                                Text(entry.hostname)
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(entry.fingerprint)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .padding(.leading, 30)
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                entryToDelete = entry
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("Removing a host key will cause Orbital to re-verify the fingerprint on the next connection.")
                }
            }
        }
        .navigationTitle("Known Hosts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All", role: .destructive) {
                        confirmClearAll = true
                    }
                }
            }
        }
        .task { await loadEntries() }
        .refreshable { await loadEntries() }
        .confirmationDialog(
            "Remove \"\(entryToDelete?.hostname ?? "")\"?",
            isPresented: Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let entry = entryToDelete { Task { await deleteEntry(entry) } }
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("Orbital will re-verify this host's fingerprint on the next connection.")
        }
        .confirmationDialog(
            "Clear All Known Hosts?",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task { await clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All cached host key fingerprints will be removed. Orbital will re-verify each server on the next connection.")
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Data

    private func loadEntries() async {
        isLoading = true
        defer { isLoading = false }

        let allKeys = (try? await KeychainService.shared.allKeys()) ?? []
        let hostKeys = allKeys.filter { $0.hasPrefix("hostkey:") }

        entries = hostKeys.compactMap { key in
            let hostname = String(key.dropFirst("hostkey:".count))
            guard !hostname.isEmpty else { return nil }
            let fingerprint = KeychainService.shared.loadIfPresent(key: key)
                .flatMap { String(data: $0, encoding: .utf8) }
                ?? "(fingerprint unavailable)"
            return KnownHostEntry(keychainKey: key, hostname: hostname, fingerprint: fingerprint)
        }
        .sorted { $0.hostname.localizedCaseInsensitiveCompare($1.hostname) == .orderedAscending }
    }

    private func deleteEntry(_ entry: KnownHostEntry) async {
        do {
            try await KeychainService.shared.delete(key: entry.keychainKey)
            await loadEntries()
        } catch {
            self.error = error.localizedDescription
        }
        entryToDelete = nil
    }

    private func clearAll() async {
        do {
            for entry in entries {
                try await KeychainService.shared.delete(key: entry.keychainKey)
            }
            await loadEntries()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        KnownHostsView()
    }
}
