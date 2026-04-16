//
//  SSHService.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbital", category: "SSHService")

// MARK: - Connection Status

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected:   return "Offline"
        case .connecting:     return "Connecting"
        case .connected:      return "Online"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected:   return "circle.fill"
        case .connecting:     return "circle.dotted"
        case .connected:      return "circle.fill"
        case .error:          return "exclamationmark.circle.fill"
        }
    }

    var colorName: String {
        switch self {
        case .connected:    return "green"
        case .connecting:   return "yellow"
        case .disconnected: return "gray"
        case .error:        return "red"
        }
    }
}

struct SSHTerminalSize: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let pixelWidth: Int
    let pixelHeight: Int

    init(columns: Int, rows: Int, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.columns = columns
        self.rows = rows
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    nonisolated static let `default` = SSHTerminalSize(columns: 80, rows: 24)
}

struct SSHCommandResult: Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitStatus: Int32

    var standardOutputString: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    var standardErrorString: String {
        String(decoding: standardError, as: UTF8.self)
    }
}

enum SSHAuthenticationMaterial: Sendable {
    case password(username: String, password: String)
    case privateKey(username: String, privateKeyData: Data)
}

struct SSHConnectionTarget: Sendable {
    let serverID: UUID
    let serverName: String
    let host: String
    let port: Int
    let username: String
    let authMethod: AuthMethod
    let credentialRef: String

    init(server: Server) {
        self.serverID = server.id
        self.serverName = server.name
        self.host = server.host
        self.port = server.port
        self.username = server.username
        self.authMethod = server.authMethod
        self.credentialRef = server.credentialRef
    }

    init(
        serverID: UUID,
        serverName: String,
        host: String,
        port: Int,
        username: String,
        authMethod: AuthMethod,
        credentialRef: String
    ) {
        self.serverID = serverID
        self.serverName = serverName
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.credentialRef = credentialRef
    }
}

struct SSHHostKeyVerifier: Sendable {
    let host: String

    private var keychainKey: String {
        "hostkey:\(host)"
    }

    func validate(fingerprint: String) async throws {
        let stored = await KeychainService.shared.loadIfPresent(key: keychainKey)
            .flatMap { String(data: $0, encoding: .utf8) }

        if let stored {
            guard stored == fingerprint else {
                throw SSHServiceError.hostKeyMismatch
            }
            return
        }

        guard let data = fingerprint.data(using: .utf8) else {
            throw SSHServiceError.hostKeyMismatch
        }
        try await KeychainService.shared.save(key: keychainKey, data: data)
    }
}

// MARK: - Backend Contracts

protocol SSHSessionTransport: AnyObject {
    func write(_ data: Data)
    func resize(to size: SSHTerminalSize)
    func close()
}

protocol SSHCommandTransport: Sendable {
    func run(command: String) async throws -> SSHCommandResult
    func close() async
}

protocol SSHBackend: Sendable {
    func connect(to target: SSHConnectionTarget, initialTerminalSize: SSHTerminalSize) async throws -> SSHSession
    func makeCommandTransport(to target: SSHConnectionTarget) async throws -> any SSHCommandTransport
    func presentableError(from error: any Error) -> any Error
}

// MARK: - SSH Session

/// A live SSH shell session. Exposes an output stream for the terminal UI.
final class SSHSession: Identifiable {
    let id: UUID = UUID()
    let serverID: UUID
    let serverName: String

    private let transport: any SSHSessionTransport
    private let outputBuffer = SSHSessionOutputBuffer()
    private let outputRelayTask: Task<Void, Never>

    init(
        serverID: UUID,
        serverName: String,
        transport: any SSHSessionTransport,
        outputStream: AsyncStream<Data>
    ) {
        self.serverID = serverID
        self.serverName = serverName
        self.transport = transport
        self.outputRelayTask = Task { [outputBuffer] in
            for await chunk in outputStream {
                await outputBuffer.publish(chunk)
            }
            await outputBuffer.finish()
        }
    }

    deinit {
        outputRelayTask.cancel()
        let outputBuffer = outputBuffer
        Task {
            await outputBuffer.finish()
        }
    }

    /// Raw bytes arriving from the remote shell, prefixed with any buffered output
    /// already seen by this session so terminal views can reopen without rendering blank.
    var outputStream: AsyncStream<Data> {
        outputBuffer.makeStream()
    }

    func write(_ data: Data) {
        transport.write(data)
    }

    func resize(to size: SSHTerminalSize) {
        transport.resize(to: size)
    }

    func close() {
        outputRelayTask.cancel()
        let outputBuffer = outputBuffer
        Task {
            await outputBuffer.finish()
        }
        transport.close()
    }
}

private actor SSHSessionOutputBuffer {
    private var history = Data()
    private var continuations: [UUID: AsyncStream<Data>.Continuation] = [:]
    private var isFinished = false

    nonisolated func makeStream() -> AsyncStream<Data> {
        let streamID = UUID()
        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            Task {
                await self.register(continuation, id: streamID)
            }
        }
    }

    func publish(_ chunk: Data) {
        guard !isFinished else { return }
        history.append(chunk)
        for continuation in continuations.values {
            continuation.yield(chunk)
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func register(_ continuation: AsyncStream<Data>.Continuation, id: UUID) {
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task {
                await self.removeContinuation(id: id)
            }
        }

        if !history.isEmpty {
            continuation.yield(history)
        }

        if isFinished {
            continuation.finish()
            return
        }

        continuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

// MARK: - Auth Material Helper

func authenticationMaterial(for target: SSHConnectionTarget) async throws -> SSHAuthenticationMaterial {
    switch target.authMethod {
    case .password:
        log.debug("[\(target.serverName)] Auth method: password, user=\(target.username)")
        let password: String
        if target.credentialRef.isEmpty {
            log.warning("[\(target.serverName)] credentialRef is empty — connecting with empty password")
            password = ""
        } else {
            password = try await KeychainService.shared.loadString(key: target.credentialRef)
            log.debug("[\(target.serverName)] Loaded password credential from Keychain")
        }
        return .password(username: target.username, password: password)

    case .privateKey:
        log.debug("[\(target.serverName)] Auth method: privateKey, user=\(target.username)")
        let keyData = try await KeychainService.shared.load(key: target.credentialRef)
        log.debug("[\(target.serverName)] Loaded \(keyData.count)-byte key from Keychain")
        return .privateKey(username: target.username, privateKeyData: keyData)
    }
}

// MARK: - SSH Service

@Observable
@MainActor
final class SSHService {
    static let shared = SSHService()
    private let backend = LibsshBackend()
    private let commandPool = SSHCommandPool()

    private(set) var statuses: [UUID: ConnectionStatus] = [:]
    private(set) var sessions: [UUID: SSHSession] = [:]

    func status(for serverID: UUID) -> ConnectionStatus {
        statuses[serverID] ?? .disconnected
    }

    func session(for serverID: UUID) -> SSHSession? {
        sessions[serverID]
    }

    // MARK: Connect

    func connect(
        to server: Server,
        initialTerminalSize: SSHTerminalSize = .default
    ) async throws -> SSHSession {
        statuses[server.id] = .connecting
        do {
            let target = SSHConnectionTarget(server: server)
            let session = try await backend.connect(to: target, initialTerminalSize: initialTerminalSize)
            sessions[server.id] = session
            statuses[server.id] = .connected
            return session
        } catch {
            let presentableError = backend.presentableError(from: error)
            statuses[server.id] = .error(presentableError.localizedDescription)
            throw presentableError
        }
    }

    func runCommand(
        _ command: String,
        on server: Server
    ) async throws -> SSHCommandResult {
        do {
            let result = try await commandPool.run(
                command: command,
                on: SSHConnectionTarget(server: server),
                using: backend
            )
            statuses[server.id] = .connected
            return result
        } catch {
            let presentableError = backend.presentableError(from: error)
            if sessions[server.id] == nil {
                statuses[server.id] = .error(presentableError.localizedDescription)
            }
            throw presentableError
        }
    }

    /// Runs a single command on a one-off connection that bypasses the persistent pool.
    /// The transport is created, used once, and immediately closed.
    /// Intended for deployment/setup operations where no cached session should be left open.
    func runCommandOnce(_ command: String, onTarget target: SSHConnectionTarget) async throws -> SSHCommandResult {
        let transport = try await backend.makeCommandTransport(to: target)
        defer { Task { await transport.close() } }
        do {
            return try await transport.run(command: command)
        } catch {
            throw backend.presentableError(from: error)
        }
    }

    // MARK: Disconnect

    func disconnect(serverID: UUID) {
        sessions[serverID]?.close()
        sessions.removeValue(forKey: serverID)
        statuses[serverID] = .disconnected
        Task {
            await commandPool.disconnect(serverID: serverID)
        }
    }

    func disconnectCommandTransport(serverID: UUID) async {
        await commandPool.disconnect(serverID: serverID)
        if sessions[serverID] == nil {
            statuses[serverID] = .disconnected
        }
    }
}

// MARK: - Libssh Backend

final class LibsshBackend: SSHBackend, @unchecked Sendable {
    private let bridge: (any LibsshClientBridge)?

    init(bridge: (any LibsshClientBridge)? = LibsshBridgeLoader.load()) {
        self.bridge = bridge
    }

    func connect(to target: SSHConnectionTarget, initialTerminalSize: SSHTerminalSize) async throws -> SSHSession {
        guard let bridge else {
            throw SSHServiceError.backendUnavailable(
                "The libssh backend scaffold is present, but the native libssh bridge is not integrated yet."
            )
        }

        let configuration = LibsshConnectionConfiguration(
            host: target.host,
            port: target.port,
            authentication: try await authenticationMaterial(for: target),
            hostKeyVerifier: SSHHostKeyVerifier(host: target.host),
            initialTerminalSize: initialTerminalSize
        )
        return try await bridge.connect(
            configuration: configuration,
            serverID: target.serverID,
            serverName: target.serverName
        )
    }

    func makeCommandTransport(to target: SSHConnectionTarget) async throws -> any SSHCommandTransport {
        guard let bridge else {
            throw SSHServiceError.backendUnavailable(
                "The libssh backend scaffold is present, but the native libssh bridge is not integrated yet."
            )
        }

        let configuration = LibsshConnectionConfiguration(
            host: target.host,
            port: target.port,
            authentication: try await authenticationMaterial(for: target),
            hostKeyVerifier: SSHHostKeyVerifier(host: target.host),
            initialTerminalSize: .default
        )
        return try await bridge.makeCommandTransport(
            configuration: configuration,
            serverName: target.serverName
        )
    }

    func presentableError(from error: any Error) -> any Error {
        if error is SSHServiceError {
            return error
        }

        if let localizedError = error as? any LocalizedError,
           let description = localizedError.errorDescription {
            return SSHServiceError.sshLibraryError(description)
        }

        return SSHServiceError.sshLibraryError(error.localizedDescription)
    }
}

// MARK: - Errors

enum SSHServiceError: LocalizedError {
    case hostKeyMismatch
    case unexpectedChannelType
    case noCredential
    case authenticationRejected(method: String)
    case authenticationTimedOut
    case connectionClosedBeforeAuthentication
    case sshLibraryError(String)
    case backendUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .hostKeyMismatch:
            return "The server's host key has changed. Remove the stored key in Settings to reconnect."
        case .unexpectedChannelType:
            return "Unexpected SSH channel type received."
        case .noCredential:
            return "No credential is stored for this server."
        case .authenticationRejected(let method):
            return "SSH \(method) authentication was rejected by the server. Verify the credential and server SSH settings."
        case .authenticationTimedOut:
            return "SSH authentication timed out before the session became active."
        case .connectionClosedBeforeAuthentication:
            return "The SSH connection closed before authentication completed."
        case .sshLibraryError(let message):
            return message
        case .backendUnavailable(let message):
            return message
        }
    }
}
