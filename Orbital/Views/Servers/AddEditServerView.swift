//
//  AddEditServerView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftData
import SwiftUI

struct AddEditServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var server: Server?

    @State private var name = ""
    @State private var host = ""
    @State private var portText = "22"
    @State private var username = ""
    @State private var authMethod: AuthMethod = .password
    @State private var passwordCredential = ""
    @State private var selectedKeyRef = ""
    @State private var pastedPEM = ""
    @State private var storedKeys: [StoredKey] = []
    @State private var jumpHostRef = ""
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @State private var notes = ""
    @State private var colorTag = "blue"
    @State private var currentStep: ServerEditorStep = .identity

    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showAuthorizeSheet = false

    private var isEditing: Bool { server != nil }
    private var port: Int { Int(portText) ?? 22 }

    private var canSave: Bool {
        isIdentityValid && isConnectionValid
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    heroCard
                    stepRail
                    activeStepCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(editorBackground)
            .navigationTitle(isEditing ? "Edit Server" : "Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
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
        .task { await loadStoredKeys() }
        .sheet(isPresented: $showAuthorizeSheet) {
            AuthorizeKeyOnServerSheet(
                host: host,
                port: port,
                username: username,
                keyRef: selectedKeyRef
            )
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(selectedColor.opacity(0.18))
                        .frame(width: 56, height: 56)

                    Image(systemName: isEditing ? "slider.horizontal.3" : "plus.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(selectedColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(isEditing ? "Refine This Server" : "Add a New Server")
                        .font(.title3.weight(.bold))

                    Text(currentStep.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(currentStep.index + 1)/\(ServerEditorStep.allCases.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selectedColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(selectedColor.opacity(0.12), in: Capsule())
            }

            if !name.trimmingCharacters(in: .whitespaces).isEmpty || !host.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 10) {
                    Label(namePreview, systemImage: "server.rack")
                    Label(hostPreview, systemImage: "network")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            selectedColor.opacity(0.22),
                            selectedColor.opacity(0.08),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var stepRail: some View {
        HStack(spacing: 10) {
            ForEach(ServerEditorStep.allCases) { step in
                Button {
                    currentStep = step
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: step.systemImage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(stepForeground(for: step))

                        Text(step.railTitle)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .foregroundStyle(stepForeground(for: step))

                        Capsule()
                            .fill(stepIndicatorColor(for: step))
                            .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(stepBackground(for: step), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var activeStepCard: some View {
        switch currentStep {
        case .identity:
            editorCard(title: currentStep.title, subtitle: currentStep.subtitle) {
                VStack(spacing: 18) {
                    InputField(
                        title: "Display Name",
                        prompt: "Production API",
                        text: $name,
                        isRequired: true
                    )

                    ColorPickerGrid(selected: $colorTag)
                }
            }

        case .connection:
            editorCard(title: currentStep.title, subtitle: currentStep.subtitle) {
                VStack(spacing: 18) {
                    InputField(
                        title: "Hostname or IP",
                        prompt: "192.168.1.100",
                        text: $host,
                        isRequired: true
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                    HStack(spacing: 14) {
                        InputField(
                            title: "Port",
                            prompt: "22",
                            text: $portText,
                            isRequired: true
                        )
                        .keyboardType(.numberPad)

                        InputField(
                            title: "Username",
                            prompt: "root",
                            text: $username,
                            isRequired: true
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }

                    InputField(
                        title: "Jump Host",
                        prompt: "Optional bastion host",
                        text: $jumpHostRef,
                        isRequired: false
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            }

        case .authentication:
            editorCard(title: currentStep.title, subtitle: currentStep.subtitle) {
                VStack(spacing: 18) {
                    authMethodPicker

                    if authMethod == .password {
                        SecureInputField(
                            title: "Password",
                            prompt: "Optional if already in Keychain",
                            text: $passwordCredential
                        )
                    } else {
                        keyAuthSection
                    }
                }
            }

        case .details:
            editorCard(title: currentStep.title, subtitle: currentStep.subtitle) {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tags")
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 10) {
                            TextField("Add tag", text: $tagInput)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .onSubmit { addTag() }

                            Button("Add") { addTag() }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(selectedColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if !tags.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 6) {
                                        Text(tag)
                                            .font(.caption.weight(.medium))
                                        Button {
                                            tags.removeAll { $0 == tag }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notes")
                            .font(.subheadline.weight(.semibold))

                        TextField("Optional notes about this server", text: $notes, axis: .vertical)
                            .lineLimit(5...8)
                            .padding(14)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }

    private func editorCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    private var authMethodPicker: some View {
        HStack(spacing: 10) {
            ForEach(AuthMethod.allCases, id: \.self) { method in
                Button {
                    authMethod = method
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: method == .password ? "key.fill" : "doc.text.fill")
                                .font(.caption.weight(.bold))
                            Text(method.displayName)
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(method == .password ? "Use a saved password" : "Pick a stored key or paste PEM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        (authMethod == method ? selectedColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground)),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(authMethod == method ? selectedColor.opacity(0.45) : .white.opacity(0.06), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var keyAuthSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Stored keys picker
            VStack(alignment: .leading, spacing: 10) {
                Text("Stored Keys")
                    .font(.subheadline.weight(.semibold))

                if storedKeys.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "key.slash")
                            .foregroundStyle(.secondary)
                        Text("No keys found. Go to Settings → SSH Keys to add one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        ForEach(storedKeys) { key in
                            Button {
                                selectedKeyRef = key.keychainKey
                                pastedPEM = ""
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "key.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(selectedKeyRef == key.keychainKey ? selectedColor : .secondary)
                                    Text(key.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedKeyRef == key.keychainKey {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(selectedColor)
                                    }
                                }
                                .padding(14)
                                .background(
                                    selectedKeyRef == key.keychainKey
                                        ? selectedColor.opacity(0.12)
                                        : Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(
                                            selectedKeyRef == key.keychainKey ? selectedColor.opacity(0.45) : .clear,
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Manual paste
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Or Paste a Key")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !pastedPEM.isEmpty {
                        Button("Clear") {
                            pastedPEM = ""
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    } else {
                        Button("Paste") {
                            if let text = UIPasteboard.general.string {
                                pastedPEM = text
                                selectedKeyRef = ""
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                TextEditor(text: Binding(
                    get: { pastedPEM },
                    set: { newValue in
                        pastedPEM = newValue
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            selectedKeyRef = ""
                        }
                    }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: pastedPEM.isEmpty ? 64 : 160)
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                if pastedPEM.isEmpty {
                    Text("Paste a PEM-format private key to use it directly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Authorize button — visible when a stored key is selected and connection details are filled
            if !selectedKeyRef.isEmpty && !host.trimmingCharacters(in: .whitespaces).isEmpty && !username.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    showAuthorizeSheet = true
                } label: {
                    Label("Authorize on This Server", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                moveToPreviousStep()
            } label: {
                Text("Back")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OrbitalSecondaryButtonStyle())
            .opacity(currentStep == .identity ? 0.45 : 1)
            .disabled(currentStep == .identity)

            Button {
                Task {
                    if currentStep == .details {
                        await save()
                    } else {
                        moveToNextStep()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(currentStep == .details ? (isEditing ? "Save Changes" : "Create Server") : "Next")
                    if currentStep != .details {
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(OrbitalPrimaryButtonStyle(tint: selectedColor))
            .disabled(isSaving || !canProceedFromCurrentStep)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private var editorBackground: some View {
        LinearGradient(
            colors: [
                selectedColor.opacity(0.10),
                Color(uiColor: .systemGroupedBackground),
                Color(uiColor: .systemGroupedBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var selectedColor: Color {
        colorOptions.first(where: { $0.name == colorTag })?.color ?? .blue
    }

    private var namePreview: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Unnamed server" : name
    }

    private var hostPreview: String {
        host.trimmingCharacters(in: .whitespaces).isEmpty ? "Host pending" : "\(usernamePreview)@\(host)"
    }

    private var usernamePreview: String {
        username.trimmingCharacters(in: .whitespaces).isEmpty ? "user" : username
    }

    private var isIdentityValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isConnectionValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        port > 0 && port <= 65_535
    }

    private var canProceedFromCurrentStep: Bool {
        switch currentStep {
        case .identity:
            return isIdentityValid
        case .connection:
            return isConnectionValid
        case .authentication:
            return true
        case .details:
            return canSave
        }
    }

    private func stepBackground(for step: ServerEditorStep) -> Color {
        if step == currentStep {
            return selectedColor.opacity(0.16)
        }
        return Color(uiColor: .secondarySystemBackground)
    }

    private func stepForeground(for step: ServerEditorStep) -> Color {
        step == currentStep ? selectedColor : .primary
    }

    private func stepIndicatorColor(for step: ServerEditorStep) -> Color {
        if step == currentStep {
            return selectedColor
        }
        if step.index < currentStep.index {
            return selectedColor.opacity(0.55)
        }
        return .clear
    }

    private func moveToPreviousStep() {
        guard let previous = currentStep.previous else { return }
        currentStep = previous
    }

    private func moveToNextStep() {
        guard canProceedFromCurrentStep, let next = currentStep.next else { return }
        currentStep = next
    }

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

        if !server.credentialRef.isEmpty {
            if server.authMethod == .password {
                Task {
                    passwordCredential = (try? await KeychainService.shared.loadString(key: server.credentialRef)) ?? ""
                }
            } else {
                if server.credentialRef.hasPrefix("sshkey:") {
                    selectedKeyRef = server.credentialRef
                } else {
                    Task {
                        pastedPEM = (try? await KeychainService.shared.loadString(key: server.credentialRef)) ?? ""
                    }
                }
            }
        }
    }

    private func loadStoredKeys() async {
        let allKeys = (try? await KeychainService.shared.allKeys()) ?? []
        storedKeys = allKeys
            .filter { $0.hasPrefix("sshkey:") }
            .map { StoredKey(keychainKey: $0, name: String($0.dropFirst("sshkey:".count))) }
            .sorted { $0.name < $1.name }
    }

    private func save() async {
        guard canSave else { return }

        isSaving = true
        defer { isSaving = false }

        // Build a server-specific key for writing new credentials (never overwrites a managed "sshkey:" entry)
        let credentialKey: String
        if let server {
            let ref = server.credentialRef
            credentialKey = (!ref.isEmpty && !ref.hasPrefix("sshkey:")) ? ref : "server-\(server.id)"
        } else {
            credentialKey = "server-\(UUID())"
        }

        // Determine the final credentialRef and persist any new credential to keychain
        let finalCredentialRef: String
        if authMethod == .password {
            if !passwordCredential.isEmpty {
                do {
                    try await KeychainService.shared.saveString(passwordCredential, key: credentialKey)
                } catch {
                    saveError = error.localizedDescription
                    return
                }
                finalCredentialRef = credentialKey
            } else {
                // No password entered — keep existing ref (or empty for new servers)
                finalCredentialRef = server?.credentialRef.hasPrefix("sshkey:") == true ? "" : (server?.credentialRef ?? "")
            }
        } else {
            if !selectedKeyRef.isEmpty {
                // Reference an existing managed key — no new keychain write needed
                finalCredentialRef = selectedKeyRef
            } else if !pastedPEM.isEmpty {
                do {
                    try await KeychainService.shared.saveString(pastedPEM, key: credentialKey)
                } catch {
                    saveError = error.localizedDescription
                    return
                }
                finalCredentialRef = credentialKey
            } else {
                finalCredentialRef = ""
            }
        }

        if let server {
            server.name = name
            server.host = host
            server.port = port
            server.username = username
            server.authMethod = authMethod
            server.credentialRef = finalCredentialRef
            server.jumpHostRef = jumpHostRef.isEmpty ? nil : jumpHostRef
            server.tags = tags
            server.notes = notes
            server.colorTag = colorTag
        } else {
            let newServer = Server(
                name: name,
                host: host,
                port: port,
                username: username,
                authMethod: authMethod,
                credentialRef: finalCredentialRef,
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

private enum ServerEditorStep: String, CaseIterable, Identifiable {
    case identity
    case connection
    case authentication
    case details

    var id: String { rawValue }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var title: String {
        switch self {
        case .identity:
            return "Identity"
        case .connection:
            return "Connection"
        case .authentication:
            return "Authentication"
        case .details:
            return "Details"
        }
    }

    var railTitle: String {
        switch self {
        case .identity:
            return "Identity"
        case .connection:
            return "Connect"
        case .authentication:
            return "Auth"
        case .details:
            return "Details"
        }
    }

    var subtitle: String {
        switch self {
        case .identity:
            return "Give the server a recognizable name and color."
        case .connection:
            return "Set the host, port, username, and any jump host."
        case .authentication:
            return "Choose how Orbital should authenticate."
        case .details:
            return "Add tags and notes before saving."
        }
    }

    var systemImage: String {
        switch self {
        case .identity:
            return "server.rack"
        case .connection:
            return "network"
        case .authentication:
            return "key.fill"
        case .details:
            return "text.alignleft"
        }
    }

    var previous: ServerEditorStep? {
        guard index > 0 else { return nil }
        return Self.allCases[index - 1]
    }

    var next: ServerEditorStep? {
        guard index < Self.allCases.count - 1 else { return nil }
        return Self.allCases[index + 1]
    }
}

private let colorOptions: [(name: String, color: Color)] = [
    ("blue", .blue), ("indigo", .indigo), ("purple", .purple),
    ("pink", .pink), ("red", .red), ("orange", .orange),
    ("yellow", .yellow), ("green", .green), ("teal", .teal)
]

private struct InputField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let isRequired: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if isRequired {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct SecureInputField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            SecureField(prompt, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct ColorPickerGrid: View {
    @Binding var selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accent Color")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                ForEach(colorOptions, id: \.name) { option in
                    Button {
                        selected = option.name
                    } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(option.color.gradient)
                                .frame(height: 40)
                                .overlay(alignment: .topTrailing) {
                                    if selected == option.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(6)
                                    }
                                }

                            Text(option.name.capitalized)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(8)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct OrbitalPrimaryButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(tint.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.white)
    }
}

private struct OrbitalSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemBackground).opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.primary)
    }
}

#Preview {
    AddEditServerView()
        .modelContainer(for: [Server.self], inMemory: true)
}
