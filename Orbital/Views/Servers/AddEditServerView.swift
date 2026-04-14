//
//  AddEditServerView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI
import SwiftData

struct AddEditServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Non-nil when editing an existing server
    var server: Server?

    // Form state
    @State private var name = ""
    @State private var host = ""
    @State private var portText = "22"
    @State private var username = ""
    @State private var authMethod: AuthMethod = .password
    @State private var credential = ""        // password or PEM private key
    @State private var jumpHostRef = ""
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @State private var notes = ""
    @State private var colorTag = "blue"

    @State private var isSaving = false
    @State private var saveError: String?

    private var isEditing: Bool { server != nil }

    private var port: Int { Int(portText) ?? 22 }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        port > 0 && port <= 65535
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                connectionSection
                authSection
                metadataSection
            }
            .navigationTitle(isEditing ? "Edit Server" : "Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .alert("Save Failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
        .onAppear { populateFromServer() }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Identity") {
            TextField("Display name", text: $name)
                .autocorrectionDisabled()

            ColorPickerRow(selected: $colorTag)
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            TextField("Hostname or IP", text: $host)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .autocapitalization(.none)

            HStack {
                Text("Port")
                Spacer()
                TextField("22", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            TextField("Username", text: $username)
                .autocorrectionDisabled()
                .autocapitalization(.none)

            TextField("Jump host (optional)", text: $jumpHostRef)
                .autocorrectionDisabled()
                .autocapitalization(.none)
        }
    }

    private var authSection: some View {
        Section("Authentication") {
            Picker("Method", selection: $authMethod) {
                ForEach(AuthMethod.allCases, id: \.self) { method in
                    Text(method.displayName).tag(method)
                }
            }

            if authMethod == .password {
                SecureField("Password", text: $credential)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Private Key (PEM)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $credential)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }

                Button("Paste from Clipboard") {
                    if let text = UIPasteboard.general.string {
                        credential = text
                    }
                }
                .font(.caption)
            }
        }
    }

    private var metadataSection: some View {
        Section("Details") {
            // Tag input
            HStack {
                TextField("Add tag", text: $tagInput)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                    .onSubmit { addTag() }

                Button("Add") { addTag() }
                    .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text(tag)
                                .font(.caption)
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Actions

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        tagInput = ""
    }

    private func populateFromServer() {
        guard let server else { return }
        name = server.name
        host = server.host
        portText = "\(server.port)"
        username = server.username
        authMethod = server.authMethod
        jumpHostRef = server.jumpHostRef ?? ""
        tags = server.tags
        notes = server.notes
        colorTag = server.colorTag
        // Load credential from Keychain
        if !server.credentialRef.isEmpty {
            Task {
                credential = (try? await KeychainService.shared.loadString(key: server.credentialRef)) ?? ""
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // Persist credential to Keychain
        let credentialKey: String
        if let server {
            credentialKey = server.credentialRef.isEmpty ? "server-\(server.id)" : server.credentialRef
        } else {
            credentialKey = "server-\(UUID())"
        }

        if !credential.isEmpty {
            do {
                try await KeychainService.shared.saveString(credential, key: credentialKey)
            } catch {
                saveError = error.localizedDescription
                return
            }
        }

        if let server {
            // Update existing
            server.name = name
            server.host = host
            server.port = port
            server.username = username
            server.authMethod = authMethod
            server.credentialRef = credential.isEmpty ? "" : credentialKey
            server.jumpHostRef = jumpHostRef.isEmpty ? nil : jumpHostRef
            server.tags = tags
            server.notes = notes
            server.colorTag = colorTag
        } else {
            // Create new
            let newServer = Server(
                name: name,
                host: host,
                port: port,
                username: username,
                authMethod: authMethod,
                credentialRef: credential.isEmpty ? "" : credentialKey,
                jumpHostRef: jumpHostRef.isEmpty ? nil : jumpHostRef,
                tags: tags,
                notes: notes,
                colorTag: colorTag
            )
            modelContext.insert(newServer)
        }

        dismiss()
    }
}

// MARK: - Color Picker Row

private let colorOptions: [(name: String, color: Color)] = [
    ("blue", .blue), ("indigo", .indigo), ("purple", .purple),
    ("pink", .pink), ("red", .red), ("orange", .orange),
    ("yellow", .yellow), ("green", .green), ("teal", .teal)
]

struct ColorPickerRow: View {
    @Binding var selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(colorOptions, id: \.name) { option in
                    Circle()
                        .fill(option.color)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selected == option.name {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture { selected = option.name }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AddEditServerView()
        .modelContainer(for: [Server.self], inMemory: true)
}
