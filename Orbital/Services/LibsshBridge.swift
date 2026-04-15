//
//  LibsshBridge.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Crypto
import Foundation
import OSLog

#if canImport(LibsshVendor)
import LibsshVendor
#endif

private let libsshLog = Logger(subsystem: "com.orbital", category: "LibsshBridge")

struct LibsshConnectionConfiguration: Sendable {
    let host: String
    let port: Int
    let authentication: SSHAuthenticationMaterial
    let hostKeyVerifier: SSHHostKeyVerifier
    let initialTerminalSize: SSHTerminalSize
}

protocol LibsshSessionTransport: AnyObject, Sendable {
    var outputStream: AsyncStream<Data> { get }
    func write(_ data: Data)
    func resize(to size: SSHTerminalSize)
    func close()
}

protocol LibsshClientBridge: Sendable {
    func connect(
        configuration: LibsshConnectionConfiguration,
        serverID: UUID,
        serverName: String
    ) async throws -> SSHSession

    func makeCommandTransport(
        configuration: LibsshConnectionConfiguration,
        serverName: String
    ) async throws -> any SSHCommandTransport
}

enum LibsshBridgeLoader {
    static var isNativeBridgeAvailable: Bool {
        #if canImport(LibsshVendor)
        true
        #else
        false
        #endif
    }

    static func load() -> (any LibsshClientBridge)? {
        #if canImport(LibsshVendor)
        NativeLibsshClientBridge()
        #else
        nil
        #endif
    }
}

#if canImport(LibsshVendor)

enum LibsshBridgeError: LocalizedError, Sendable {
    case failedToCreateSession
    case unsupportedPrivateKeyMaterial
    case hostKeyUnavailable
    case algorithmUnavailable
    case authenticationRejected(method: String)
    case unsupportedAuthenticationMethod(requested: String, available: String)
    case library(String)

    var errorDescription: String? {
        switch self {
        case .failedToCreateSession:
            return "libssh could not create a new SSH session."
        case .unsupportedPrivateKeyMaterial:
            return "The stored private key is not in a supported format."
        case .hostKeyUnavailable:
            return "libssh could not read the server host key."
        case .algorithmUnavailable:
            return "libssh could not determine the host key algorithm."
        case .authenticationRejected(let method):
            return "SSH \(method) authentication was rejected by the server."
        case .unsupportedAuthenticationMethod(let requested, let available):
            return "The server does not allow \(requested) authentication. Available methods: \(available)."
        case .library(let message):
            return message
        }
    }
}

private final class NativeLibsshClientBridge: LibsshClientBridge {
    func connect(
        configuration: LibsshConnectionConfiguration,
        serverID: UUID,
        serverName: String
    ) async throws -> SSHSession {
        let transport = try await NativeLibsshSessionTransport.establish(
            configuration: configuration,
            serverName: serverName
        )
        return SSHSession(
            serverID: serverID,
            serverName: serverName,
            backendKind: .libssh,
            transport: transport,
            outputStream: transport.outputStream
        )
    }

    func makeCommandTransport(
        configuration: LibsshConnectionConfiguration,
        serverName: String
    ) async throws -> any SSHCommandTransport {
        NativeLibsshCommandTransport(
            configuration: configuration,
            serverName: serverName
        )
    }
}

private actor CommandConnectTaskCoordinator {
    private var task: Task<Void, Error>?

    func acquireTask(
        create: @escaping @Sendable () -> Task<Void, Error>
    ) -> (task: Task<Void, Error>, created: Bool) {
        if let task {
            return (task, false)
        }

        let newTask = create()
        task = newTask
        return (newTask, true)
    }

    func clear() {
        task = nil
    }
}

private final class NativeLibsshCommandTransport: SSHCommandTransport, @unchecked Sendable {
    private let configuration: LibsshConnectionConfiguration
    private let serverName: String
    private let queue: DispatchQueue
    private let connectCoordinator = CommandConnectTaskCoordinator()

    private var session: ssh_session?
    private var isClosed = false

    init(
        configuration: LibsshConnectionConfiguration,
        serverName: String
    ) {
        self.configuration = configuration
        self.serverName = serverName
        self.queue = DispatchQueue(label: "dev.orbital.libssh.command.\(serverName)")
    }

    func run(command: String) async throws -> SSHCommandResult {
        try await ensureConnected()

        do {
            return try await performOnQueue {
                try self.runCommandLocked(command)
            }
        } catch {
            libsshLog.error("[\(self.serverName)] Command failed on cached libssh session; reconnecting: \(error.localizedDescription, privacy: .public)")
            await resetConnection()
            try await ensureConnected()
            return try await performOnQueue {
                try self.runCommandLocked(command)
            }
        }
    }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.shutdownLocked()
                continuation.resume()
            }
        }
    }

    private func ensureConnected() async throws {
        if try await isConnected() {
            return
        }

        let (task, createdTask) = await connectCoordinator.acquireTask {
            Task { [weak self] in
                guard let self else { return }
                try await self.establishConnection()
            }
        }

        do {
            try await task.value
            if createdTask {
                await connectCoordinator.clear()
            }
        } catch {
            if createdTask {
                await connectCoordinator.clear()
            }
            throw error
        }
    }

    private func establishConnection() async throws {
        let fingerprint = try await performOnQueue {
            try self.connectAndCollectHostKeyFingerprintLocked()
        }

        do {
            try await configuration.hostKeyVerifier.validate(fingerprint: fingerprint)
        } catch {
            await resetConnection()
            throw error
        }

        do {
            try await performOnQueue {
                try self.authenticateLocked()
            }
        } catch {
            await resetConnection()
            throw error
        }

        libsshLog.info("[\(self.serverName)] Persistent libssh command session authenticated")
    }

    private func isConnected() async throws -> Bool {
        try await performOnQueue {
            guard !self.isClosed, let session = self.session else { return false }
            return ssh_is_connected(session) == 1
        }
    }

    private func connectAndCollectHostKeyFingerprintLocked() throws -> String {
        guard !isClosed else {
            throw LibsshBridgeError.library("The SSH command transport is closed.")
        }

        shutdownSessionLocked()

        guard let session = ssh_new() else {
            throw LibsshBridgeError.failedToCreateSession
        }

        self.session = session
        ssh_set_blocking(session, 1)

        var port = Int32(configuration.port)
        var timeoutSeconds = Int32(15)
        var processConfig = Int32(0)
        var logVerbosity = Int32(SSH_LOG_NOLOG)

        try setOption(session: session, option: SSH_OPTIONS_HOST, string: configuration.host)
        try setOption(session: session, option: SSH_OPTIONS_USER, string: username(for: configuration.authentication))
        try setOption(session: session, option: SSH_OPTIONS_PORT, intPointer: &port)
        try setOption(session: session, option: SSH_OPTIONS_TIMEOUT, intPointer: &timeoutSeconds)
        try setOption(session: session, option: SSH_OPTIONS_PROCESS_CONFIG, intPointer: &processConfig)
        try setOption(session: session, option: SSH_OPTIONS_LOG_VERBOSITY, intPointer: &logVerbosity)

        libsshLog.info("[\(self.serverName)] Opening persistent libssh command session to \(self.configuration.host):\(self.configuration.port)")
        guard ssh_connect(session) == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "libssh failed to connect to the SSH server.")
        }

        return try hostKeyFingerprint(session: session)
    }

    private func authenticateLocked() throws {
        guard !isClosed, let session else {
            throw LibsshBridgeError.failedToCreateSession
        }

        let noneResult = ssh_userauth_none(session, nil)
        if noneResult == SSH_AUTH_SUCCESS.rawValue {
            return
        }

        let availableMethods = ssh_userauth_list(session, nil)
        try authenticate(
            session: session,
            availableMethods: availableMethods,
            authentication: configuration.authentication
        )
    }

    private func runCommandLocked(_ command: String) throws -> SSHCommandResult {
        guard !isClosed, let session else {
            throw LibsshBridgeError.library("The SSH command transport is closed.")
        }
        guard ssh_is_connected(session) == 1 else {
            throw makeLibraryError(session: session, fallback: "The persistent SSH session is no longer connected.")
        }

        guard let channel = ssh_channel_new(session) else {
            throw makeLibraryError(session: session, fallback: "libssh failed to allocate a command channel.")
        }

        defer {
            ssh_channel_send_eof(channel)
            ssh_channel_close(channel)
            ssh_channel_free(channel)
        }

        guard ssh_channel_open_session(channel) == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "The SSH server rejected the command session.")
        }

        let execResult = command.withCString { pointer in
            ssh_channel_request_exec(channel, pointer)
        }
        guard execResult == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "The SSH server rejected the command request.")
        }

        var standardOutput = Data()
        var standardError = Data()

        while true {
            let outputCount = try readCommandStreamLocked(from: channel, isStandardError: false, into: &standardOutput)
            let errorCount = try readCommandStreamLocked(from: channel, isStandardError: true, into: &standardError)

            if ssh_channel_is_eof(channel) == 1 && outputCount == 0 && errorCount == 0 {
                break
            }
        }

        var exitCode = UInt32(0)
        if ssh_channel_get_exit_state(channel, &exitCode, nil, nil) != SSH_OK {
            throw makeLibraryError(session: session, fallback: "The SSH server did not report a command exit status.")
        }

        return SSHCommandResult(
            standardOutput: standardOutput,
            standardError: standardError,
            exitStatus: Int32(bitPattern: exitCode)
        )
    }

    private func readCommandStreamLocked(
        from channel: ssh_channel,
        isStandardError: Bool,
        into data: inout Data
    ) throws -> Int {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bufferCapacity = UInt32(buffer.count)
        let count = buffer.withUnsafeMutableBytes { rawBuffer in
            ssh_channel_read_timeout(
                channel,
                rawBuffer.baseAddress,
                bufferCapacity,
                isStandardError ? 1 : 0,
                250
            )
        }

        if count > 0 {
            data.append(contentsOf: buffer.prefix(Int(count)))
            return Int(count)
        }

        if count == 0 || count == SSH_AGAIN {
            return 0
        }

        throw makeLibraryError(session: session, fallback: "The SSH command channel read failed.")
    }

    private func authenticate(
        session: ssh_session,
        availableMethods: Int32,
        authentication: SSHAuthenticationMaterial
    ) throws {
        switch authentication {
        case .password(_, let password):
            guard (availableMethods & Int32(SSH_AUTH_METHOD_PASSWORD)) != 0 else {
                throw LibsshBridgeError.unsupportedAuthenticationMethod(
                    requested: "password",
                    available: readableAuthenticationMethods(from: availableMethods)
                )
            }

            let result = ssh_userauth_password(session, nil, password)
            guard result == SSH_AUTH_SUCCESS.rawValue else {
                if result == SSH_AUTH_DENIED.rawValue || result == SSH_AUTH_PARTIAL.rawValue {
                    throw LibsshBridgeError.authenticationRejected(method: "password")
                }
                throw makeLibraryError(session: session, fallback: "Password authentication failed.")
            }

        case .privateKey(_, let privateKeyData):
            guard (availableMethods & Int32(SSH_AUTH_METHOD_PUBLICKEY)) != 0 else {
                throw LibsshBridgeError.unsupportedAuthenticationMethod(
                    requested: "public key",
                    available: readableAuthenticationMethods(from: availableMethods)
                )
            }

            let privateKeyText = try normalizedPrivateKeyString(from: privateKeyData)
            var key: ssh_key?
            let importResult = privateKeyText.withCString { keyText in
                ssh_pki_import_privkey_base64(keyText, nil, nil, nil, &key)
            }
            guard importResult == SSH_OK, let key else {
                throw makeLibraryError(session: session, fallback: "libssh could not import the stored private key.")
            }
            defer { ssh_key_free(key) }

            let result = ssh_userauth_publickey(session, nil, key)
            guard result == SSH_AUTH_SUCCESS.rawValue else {
                if result == SSH_AUTH_DENIED.rawValue || result == SSH_AUTH_PARTIAL.rawValue {
                    throw LibsshBridgeError.authenticationRejected(method: "public key")
                }
                throw makeLibraryError(session: session, fallback: "Public key authentication failed.")
            }
        }
    }

    private func hostKeyFingerprint(session: ssh_session) throws -> String {
        var key: ssh_key?
        guard ssh_get_server_publickey(session, &key) == SSH_OK, let key else {
            throw LibsshBridgeError.hostKeyUnavailable
        }
        defer { ssh_key_free(key) }

        guard let algorithmPointer = ssh_key_type_to_char(ssh_key_type(key)) else {
            throw LibsshBridgeError.algorithmUnavailable
        }

        var base64Pointer: UnsafeMutablePointer<CChar>?
        guard ssh_pki_export_pubkey_base64(key, &base64Pointer) == SSH_OK, let base64Pointer else {
            throw makeLibraryError(session: session, fallback: "libssh could not export the server host key.")
        }
        defer { ssh_string_free_char(base64Pointer) }

        let algorithm = String(cString: algorithmPointer)
        let base64 = String(cString: base64Pointer)
        return "\(algorithm) \(base64)"
    }

    private func normalizedPrivateKeyString(from data: Data) throws -> String {
        if data.count == 32 {
            return try openSSHPrivateKey(fromRawEd25519Seed: data)
        }

        guard let string = String(data: data, encoding: .utf8) else {
            throw LibsshBridgeError.unsupportedPrivateKeyMaterial
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibsshBridgeError.unsupportedPrivateKeyMaterial
        }
        return trimmed
    }

    private func openSSHPrivateKey(fromRawEd25519Seed seed: Data) throws -> String {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let publicKey = Data(privateKey.publicKey.rawRepresentation)
        let privateKeyPayload = seed + publicKey

        var publicBlob = Data()
        appendSSHString("ssh-ed25519", to: &publicBlob)
        appendSSHString(publicKey, to: &publicBlob)

        var privateBlob = Data()
        let check = UInt32.random(in: .min ... .max)
        appendUInt32(check, to: &privateBlob)
        appendUInt32(check, to: &privateBlob)
        appendSSHString("ssh-ed25519", to: &privateBlob)
        appendSSHString(publicKey, to: &privateBlob)
        appendSSHString(privateKeyPayload, to: &privateBlob)
        appendSSHString(Data("orbital".utf8), to: &privateBlob)

        var paddingByte: UInt8 = 1
        while privateBlob.count % 8 != 0 {
            privateBlob.append(paddingByte)
            paddingByte &+= 1
        }

        var envelope = Data()
        envelope.append(Data("openssh-key-v1".utf8))
        envelope.append(0)
        appendSSHString("none", to: &envelope)
        appendSSHString("none", to: &envelope)
        appendSSHString(Data(), to: &envelope)
        appendUInt32(1, to: &envelope)
        appendSSHString(publicBlob, to: &envelope)
        appendSSHString(privateBlob, to: &envelope)

        let base64 = envelope.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return """
        -----BEGIN OPENSSH PRIVATE KEY-----
        \(base64)
        -----END OPENSSH PRIVATE KEY-----
        """
    }

    private func appendSSHString(_ string: String, to data: inout Data) {
        appendSSHString(Data(string.utf8), to: &data)
    }

    private func appendSSHString(_ payload: Data, to data: inout Data) {
        appendUInt32(UInt32(payload.count), to: &data)
        data.append(payload)
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private func readableAuthenticationMethods(from mask: Int32) -> String {
        let knownMethods: [(Int32, String)] = [
            (Int32(SSH_AUTH_METHOD_PUBLICKEY), "public key"),
            (Int32(SSH_AUTH_METHOD_PASSWORD), "password"),
            (Int32(SSH_AUTH_METHOD_INTERACTIVE), "keyboard-interactive"),
            (Int32(SSH_AUTH_METHOD_HOSTBASED), "host based"),
        ]
        let names = knownMethods.compactMap { (mask & $0.0) != 0 ? $0.1 : nil }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private func username(for authentication: SSHAuthenticationMaterial) -> String {
        switch authentication {
        case .password(let username, _), .privateKey(let username, _):
            return username
        }
    }

    private func setOption(
        session: ssh_session,
        option: ssh_options_e,
        string: String
    ) throws {
        let result = string.withCString { value in
            ssh_options_set(session, option, value)
        }
        guard result == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "libssh rejected an SSH string option.")
        }
    }

    private func setOption(
        session: ssh_session,
        option: ssh_options_e,
        intPointer: UnsafeMutablePointer<Int32>
    ) throws {
        guard ssh_options_set(session, option, intPointer) == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "libssh rejected an SSH integer option.")
        }
    }

    private func makeLibraryError(session: ssh_session?, fallback: String) -> LibsshBridgeError {
        LibsshBridgeError.library(lastErrorMessage(session: session, fallback: fallback))
    }

    private func lastErrorMessage(
        session: ssh_session? = nil,
        fallback: String
    ) -> String {
        let activeSession = session ?? self.session
        guard let activeSession,
              let errorPointer = ssh_get_error(UnsafeMutableRawPointer(activeSession)) else {
            return fallback
        }
        let message = String(cString: errorPointer).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }

    private func shutdownSessionLocked() {
        guard let session else { return }
        ssh_disconnect(session)
        ssh_free(session)
        self.session = nil
    }

    private func shutdownLocked() {
        guard !isClosed else {
            shutdownSessionLocked()
            return
        }

        isClosed = true
        shutdownSessionLocked()
    }

    private func resetConnection() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.shutdownSessionLocked()
                continuation.resume()
            }
        }
    }

    private func performOnQueue<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class NativeLibsshSessionTransport: LibsshSessionTransport, SSHSessionTransport, @unchecked Sendable {
    let outputStream: AsyncStream<Data>

    private let serverName: String
    private let queue: DispatchQueue
    private let continuation: AsyncStream<Data>.Continuation

    private var session: ssh_session?
    private var channel: ssh_channel?
    private var isClosed = false
    private var isFinished = false

    private init(serverName: String) {
        self.serverName = serverName
        self.queue = DispatchQueue(label: "dev.orbital.libssh.\(serverName)")
        let stream = AsyncStream<Data>.makeStream()
        self.outputStream = stream.stream
        self.continuation = stream.continuation
    }

    deinit {
        close()
    }

    static func establish(
        configuration: LibsshConnectionConfiguration,
        serverName: String
    ) async throws -> NativeLibsshSessionTransport {
        let transport = NativeLibsshSessionTransport(serverName: serverName)
        do {
            let fingerprint = try await transport.performOnQueue {
                try transport.connectAndCollectHostKeyFingerprint(configuration: configuration)
            }
            do {
                try await configuration.hostKeyVerifier.validate(fingerprint: fingerprint)
            } catch {
                await transport.shutdown()
                throw error
            }
            try await transport.performOnQueue {
                try transport.authenticateAndOpenShell(configuration: configuration)
            }
            transport.startReadPump()
            return transport
        } catch {
            await transport.shutdown()
            throw error
        }
    }

    func write(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.writeLocked(data)
            } catch {
                self.failLocked(error)
            }
        }
    }

    func resize(to size: SSHTerminalSize) {
        queue.async { [weak self] in
            guard let self, !self.isClosed, let channel = self.channel else { return }
            let result = ssh_channel_change_pty_size(
                channel,
                Int32(size.columns),
                Int32(size.rows)
            )
            if result != SSH_OK {
                libsshLog.error("[\(self.serverName)] PTY resize failed: \(self.lastErrorMessage(fallback: "Unable to resize remote PTY"), privacy: .public)")
            }
        }
    }

    func close() {
        queue.async { [weak self] in
            self?.shutdownLocked()
        }
    }

    private func connectAndCollectHostKeyFingerprint(
        configuration: LibsshConnectionConfiguration
    ) throws -> String {
        guard let session = ssh_new() else {
            throw LibsshBridgeError.failedToCreateSession
        }

        self.session = session
        ssh_set_blocking(session, 1)

        var port = Int32(configuration.port)
        var timeoutSeconds = Int32(15)
        var processConfig = Int32(0)
        var logVerbosity = Int32(SSH_LOG_NOLOG)

        try setOption(session: session, option: SSH_OPTIONS_HOST, string: configuration.host)
        try setOption(session: session, option: SSH_OPTIONS_USER, string: username(for: configuration.authentication))
        try setOption(session: session, option: SSH_OPTIONS_PORT, intPointer: &port)
        try setOption(session: session, option: SSH_OPTIONS_TIMEOUT, intPointer: &timeoutSeconds)
        try setOption(session: session, option: SSH_OPTIONS_PROCESS_CONFIG, intPointer: &processConfig)
        try setOption(session: session, option: SSH_OPTIONS_LOG_VERBOSITY, intPointer: &logVerbosity)

        libsshLog.info("[\(self.serverName)] Connecting with libssh to \(configuration.host):\(configuration.port)")
        guard ssh_connect(session) == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "libssh failed to connect to the SSH server.")
        }

        return try hostKeyFingerprint(session: session)
    }

    private func authenticateAndOpenShell(configuration: LibsshConnectionConfiguration) throws {
        guard let session else {
            throw LibsshBridgeError.failedToCreateSession
        }

        let noneResult = ssh_userauth_none(session, nil)
        if noneResult != SSH_AUTH_SUCCESS.rawValue {
            let availableMethods = ssh_userauth_list(session, nil)
            try authenticate(
                session: session,
                availableMethods: availableMethods,
                authentication: configuration.authentication
            )
        }

        guard let channel = ssh_channel_new(session) else {
            throw makeLibraryError(session: session, fallback: "libssh failed to allocate a session channel.")
        }

        self.channel = channel

        guard ssh_channel_open_session(channel) == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "The SSH server rejected the session channel.")
        }

        let size = configuration.initialTerminalSize
        guard ssh_channel_request_pty_size(channel, "xterm-256color", Int32(size.columns), Int32(size.rows)) == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "The SSH server rejected the PTY request.")
        }

        guard ssh_channel_request_shell(channel) == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "The SSH server rejected the shell request.")
        }

        ssh_channel_set_blocking(channel, 0)
        ssh_set_blocking(session, 0)
        libsshLog.info("[\(self.serverName)] libssh session authenticated and shell opened")
    }

    private func authenticate(
        session: ssh_session,
        availableMethods: Int32,
        authentication: SSHAuthenticationMaterial
    ) throws {
        switch authentication {
        case .password(_, let password):
            guard (availableMethods & Int32(SSH_AUTH_METHOD_PASSWORD)) != 0 else {
                throw LibsshBridgeError.unsupportedAuthenticationMethod(
                    requested: "password",
                    available: readableAuthenticationMethods(from: availableMethods)
                )
            }

            let result = ssh_userauth_password(session, nil, password)
            guard result == SSH_AUTH_SUCCESS.rawValue else {
                if result == SSH_AUTH_DENIED.rawValue || result == SSH_AUTH_PARTIAL.rawValue {
                    throw LibsshBridgeError.authenticationRejected(method: "password")
                }
                throw makeLibraryError(session: session, fallback: "Password authentication failed.")
            }

        case .privateKey(_, let privateKeyData):
            guard (availableMethods & Int32(SSH_AUTH_METHOD_PUBLICKEY)) != 0 else {
                throw LibsshBridgeError.unsupportedAuthenticationMethod(
                    requested: "public key",
                    available: readableAuthenticationMethods(from: availableMethods)
                )
            }

            let privateKeyText = try normalizedPrivateKeyString(from: privateKeyData)
            var key: ssh_key?
            let importResult = privateKeyText.withCString { keyText in
                ssh_pki_import_privkey_base64(keyText, nil, nil, nil, &key)
            }
            guard importResult == SSH_OK, let key else {
                throw makeLibraryError(session: session, fallback: "libssh could not import the stored private key.")
            }
            defer { ssh_key_free(key) }

            let result = ssh_userauth_publickey(session, nil, key)
            guard result == SSH_AUTH_SUCCESS.rawValue else {
                if result == SSH_AUTH_DENIED.rawValue || result == SSH_AUTH_PARTIAL.rawValue {
                    throw LibsshBridgeError.authenticationRejected(method: "public key")
                }
                throw makeLibraryError(session: session, fallback: "Public key authentication failed.")
            }
        }
    }

    private func startReadPump() {
        queue.async { [weak self] in
            self?.pumpReads()
        }
    }

    private func pumpReads() {
        guard !isClosed, let channel else {
            finishLocked()
            return
        }

        let pollResult = ssh_channel_poll_timeout(channel, 50, 0)
        if pollResult == SSH_ERROR {
            failLocked(makeLibraryError(session: session, fallback: "The SSH channel closed unexpectedly."))
            return
        }

        if pollResult > 0 {
            do {
                try readAvailableLocked(from: channel)
            } catch {
                failLocked(error)
                return
            }
        }

        if ssh_channel_is_eof(channel) == 1 || ssh_channel_is_closed(channel) == 1 {
            shutdownLocked()
            return
        }

        queue.async { [weak self] in
            self?.pumpReads()
        }
    }

    private func readAvailableLocked(from channel: ssh_channel) throws {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bufferCapacity = UInt32(buffer.count)

        while !isClosed {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                ssh_channel_read_nonblocking(
                    channel,
                    rawBuffer.baseAddress,
                    bufferCapacity,
                    0
                )
            }

            if count > 0 {
                continuation.yield(Data(buffer.prefix(Int(count))))
                continue
            }

            if count == SSH_ERROR {
                throw makeLibraryError(session: session, fallback: "The SSH channel read failed.")
            }

            return
        }
    }

    private func writeLocked(_ data: Data) throws {
        guard !isClosed, let channel else { return }

        var offset = 0
        while offset < data.count && !isClosed {
            let written: Int32 = data.withUnsafeBytes { rawBuffer in
                let baseAddress = rawBuffer.baseAddress?.advanced(by: offset)
                return ssh_channel_write(channel, baseAddress, UInt32(data.count - offset))
            }

            if written > 0 {
                offset += Int(written)
                continue
            }

            if written == SSH_AGAIN {
                continue
            }

            throw makeLibraryError(session: session, fallback: "The SSH channel write failed.")
        }
    }

    private func hostKeyFingerprint(session: ssh_session) throws -> String {
        var key: ssh_key?
        guard ssh_get_server_publickey(session, &key) == SSH_OK, let key else {
            throw LibsshBridgeError.hostKeyUnavailable
        }
        defer { ssh_key_free(key) }

        guard let algorithmPointer = ssh_key_type_to_char(ssh_key_type(key)) else {
            throw LibsshBridgeError.algorithmUnavailable
        }

        var base64Pointer: UnsafeMutablePointer<CChar>?
        guard ssh_pki_export_pubkey_base64(key, &base64Pointer) == SSH_OK, let base64Pointer else {
            throw makeLibraryError(session: session, fallback: "libssh could not export the server host key.")
        }
        defer { ssh_string_free_char(base64Pointer) }

        let algorithm = String(cString: algorithmPointer)
        let base64 = String(cString: base64Pointer)
        return "\(algorithm) \(base64)"
    }

    private func normalizedPrivateKeyString(from data: Data) throws -> String {
        if data.count == 32 {
            return try openSSHPrivateKey(fromRawEd25519Seed: data)
        }

        guard let string = String(data: data, encoding: .utf8) else {
            throw LibsshBridgeError.unsupportedPrivateKeyMaterial
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibsshBridgeError.unsupportedPrivateKeyMaterial
        }
        return trimmed
    }

    private func openSSHPrivateKey(fromRawEd25519Seed seed: Data) throws -> String {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let publicKey = Data(privateKey.publicKey.rawRepresentation)
        let privateKeyPayload = seed + publicKey

        var publicBlob = Data()
        appendSSHString("ssh-ed25519", to: &publicBlob)
        appendSSHString(publicKey, to: &publicBlob)

        var privateBlob = Data()
        let check = UInt32.random(in: .min ... .max)
        appendUInt32(check, to: &privateBlob)
        appendUInt32(check, to: &privateBlob)
        appendSSHString("ssh-ed25519", to: &privateBlob)
        appendSSHString(publicKey, to: &privateBlob)
        appendSSHString(privateKeyPayload, to: &privateBlob)
        appendSSHString(Data("orbital".utf8), to: &privateBlob)

        var paddingByte: UInt8 = 1
        while privateBlob.count % 8 != 0 {
            privateBlob.append(paddingByte)
            paddingByte &+= 1
        }

        var envelope = Data()
        envelope.append(Data("openssh-key-v1".utf8))
        envelope.append(0)
        appendSSHString("none", to: &envelope)
        appendSSHString("none", to: &envelope)
        appendSSHString(Data(), to: &envelope)
        appendUInt32(1, to: &envelope)
        appendSSHString(publicBlob, to: &envelope)
        appendSSHString(privateBlob, to: &envelope)

        let base64 = envelope.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return """
        -----BEGIN OPENSSH PRIVATE KEY-----
        \(base64)
        -----END OPENSSH PRIVATE KEY-----
        """
    }

    private func appendSSHString(_ string: String, to data: inout Data) {
        appendSSHString(Data(string.utf8), to: &data)
    }

    private func appendSSHString(_ payload: Data, to data: inout Data) {
        appendUInt32(UInt32(payload.count), to: &data)
        data.append(payload)
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private func readableAuthenticationMethods(from mask: Int32) -> String {
        let knownMethods: [(Int32, String)] = [
            (Int32(SSH_AUTH_METHOD_PUBLICKEY), "public key"),
            (Int32(SSH_AUTH_METHOD_PASSWORD), "password"),
            (Int32(SSH_AUTH_METHOD_INTERACTIVE), "keyboard-interactive"),
            (Int32(SSH_AUTH_METHOD_HOSTBASED), "host based"),
        ]
        let names = knownMethods.compactMap { (mask & $0.0) != 0 ? $0.1 : nil }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private func username(for authentication: SSHAuthenticationMaterial) -> String {
        switch authentication {
        case .password(let username, _), .privateKey(let username, _):
            return username
        }
    }

    private func setOption(
        session: ssh_session,
        option: ssh_options_e,
        string: String
    ) throws {
        let result = string.withCString { value in
            ssh_options_set(session, option, value)
        }
        guard result == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "libssh rejected an SSH string option.")
        }
    }

    private func setOption(
        session: ssh_session,
        option: ssh_options_e,
        intPointer: UnsafeMutablePointer<Int32>
    ) throws {
        guard ssh_options_set(session, option, intPointer) == SSH_OK else {
            throw makeLibraryError(session: session, fallback: "libssh rejected an SSH integer option.")
        }
    }

    private func makeLibraryError(session: ssh_session?, fallback: String) -> LibsshBridgeError {
        LibsshBridgeError.library(lastErrorMessage(session: session, fallback: fallback))
    }

    private func lastErrorMessage(
        session: ssh_session? = nil,
        fallback: String
    ) -> String {
        let activeSession = session ?? self.session
        guard let activeSession,
              let errorPointer = ssh_get_error(UnsafeMutableRawPointer(activeSession)) else {
            return fallback
        }
        let message = String(cString: errorPointer).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }

    private func failLocked(_ error: any Error) {
        libsshLog.error("[\(self.serverName)] libssh transport failure: \(error.localizedDescription, privacy: .public)")
        shutdownLocked()
    }

    private func finishLocked() {
        guard !isFinished else { return }
        isFinished = true
        continuation.finish()
    }

    private func shutdownLocked() {
        guard !isClosed else {
            finishLocked()
            return
        }

        isClosed = true

        if let channel {
            ssh_channel_send_eof(channel)
            ssh_channel_close(channel)
            ssh_channel_free(channel)
            self.channel = nil
        }

        if let session {
            ssh_disconnect(session)
            ssh_free(session)
            self.session = nil
        }

        finishLocked()
    }

    private func shutdown() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.shutdownLocked()
                continuation.resume()
            }
        }
    }

    private func performOnQueue<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

#endif
