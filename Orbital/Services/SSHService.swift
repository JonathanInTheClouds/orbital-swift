//
//  SSHService.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
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

enum SSHBackendKind: String, CaseIterable, Identifiable {
    case nioSSH
    case libssh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nioSSH:
            return "NIOSSH"
        case .libssh:
            return "libssh"
        }
    }

    var statusDescription: String {
        switch self {
        case .nioSSH:
            return "Current in-app SSH engine"
        case .libssh:
            return LibsshBridgeLoader.isNativeBridgeAvailable
                ? "Native libssh bridge available"
                : "Native libssh bridge not integrated yet"
        }
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

enum SSHBackendFactory {
    static func makePreferredBackend() -> any SSHBackend {
        if LibsshBridgeLoader.isNativeBridgeAvailable {
            return LibsshBackend()
        }
        return NIOSSHBackend()
    }
}

// MARK: - Backend Contracts

protocol SSHSessionTransport: AnyObject {
    func write(_ data: Data)
    func resize(to size: SSHTerminalSize)
    func close()
}

protocol SSHBackend {
    var kind: SSHBackendKind { get }
    func connect(to target: SSHConnectionTarget, initialTerminalSize: SSHTerminalSize) async throws -> SSHSession
    func presentableError(from error: any Error) -> any Error
}

// MARK: - SSH Session

/// A live SSH shell session. Owns the NIO channels and exposes an output stream for the terminal UI.
final class SSHSession: Identifiable {
    let id: UUID = UUID()
    let serverID: UUID
    let serverName: String
    let backendKind: SSHBackendKind

    /// Raw bytes arriving from the remote shell. Finishes when the connection drops.
    let outputStream: AsyncStream<Data>

    private let transport: any SSHSessionTransport

    init(
        serverID: UUID,
        serverName: String,
        backendKind: SSHBackendKind,
        transport: any SSHSessionTransport,
        outputStream: AsyncStream<Data>
    ) {
        self.serverID = serverID
        self.serverName = serverName
        self.backendKind = backendKind
        self.transport = transport
        self.outputStream = outputStream
    }

    func write(_ data: Data) {
        transport.write(data)
    }

    func resize(to size: SSHTerminalSize) {
        transport.resize(to: size)
    }

    func close() {
        transport.close()
    }
}

private final class NIOSSHSessionTransport: SSHSessionTransport {
    private let tcpChannel: Channel
    private let shellChannel: Channel

    init(tcpChannel: Channel, shellChannel: Channel) {
        self.tcpChannel = tcpChannel
        self.shellChannel = shellChannel
    }

    func write(_ data: Data) {
        var buffer = shellChannel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        shellChannel.writeAndFlush(buffer, promise: nil)
    }

    func resize(to size: SSHTerminalSize) {
        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: size.columns,
            terminalRowHeight: size.rows,
            terminalPixelWidth: size.pixelWidth,
            terminalPixelHeight: size.pixelHeight
        )
        shellChannel.triggerUserOutboundEvent(request, promise: nil)
    }

    func close() {
        shellChannel.close(promise: nil)
        tcpChannel.close(promise: nil)
    }
}

// MARK: - Shell Channel Handler

/// Handles the shell child channel pipeline.
///
/// InboundIn  = SSHChannelData  — data arriving from the server
/// OutboundIn = ByteBuffer      — raw bytes written by SSHSession.write(_:)
/// OutboundOut = SSHChannelData — wrapped before sending to the server
///
/// This replaces the old SSHChannelDataUnwrapper + SSHOutboundHandler pair
/// that no longer exists in NIOSSH 0.12.0.
private final class ShellHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = Never
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let continuation: AsyncStream<Data>.Continuation
    private let initialTerminalSize: SSHTerminalSize

    init(
        _ continuation: AsyncStream<Data>.Continuation,
        initialTerminalSize: SSHTerminalSize
    ) {
        self.continuation = continuation
        self.initialTerminalSize = initialTerminalSize
    }

    // Request a PTY then a shell as soon as the child channel becomes active.
    func channelActive(context: ChannelHandlerContext) {
        log.info("[ShellHandler] channelActive — requesting PTY then shell")

        // 1. Allocate a pseudo-terminal so the server opens a proper interactive shell.
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: initialTerminalSize.columns,
            terminalRowHeight: initialTerminalSize.rows,
            terminalPixelWidth: initialTerminalSize.pixelWidth,
            terminalPixelHeight: initialTerminalSize.pixelHeight,
            terminalModes: .init([:])
        )
        let ptyPromise = context.eventLoop.makePromise(of: Void.self)
        ptyPromise.futureResult.whenComplete { result in
            switch result {
            case .success:
                log.info("[ShellHandler] PTY granted — sending shell request")
                let shellRequest = SSHChannelRequestEvent.ShellRequest(wantReply: true)
                let shellPromise = context.eventLoop.makePromise(of: Void.self)
                shellPromise.futureResult.whenComplete { shellResult in
                    switch shellResult {
                    case .success:
                        log.info("[ShellHandler] Shell opened successfully")
                    case .failure(let err):
                        log.error("[ShellHandler] Shell request failed: \(String(reflecting: err))")
                    }
                }
                context.triggerUserOutboundEvent(shellRequest, promise: shellPromise)
            case .failure(let err):
                log.error("[ShellHandler] PTY request failed: \(String(reflecting: err))")
            }
        }
        context.triggerUserOutboundEvent(ptyRequest, promise: ptyPromise)
    }

    // Unwrap incoming SSHChannelData and forward to the AsyncStream.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let sshData = unwrapInboundIn(data)
        guard case .byteBuffer(let buf) = sshData.data else { return }
        log.debug("[ShellHandler] received \(buf.readableBytes) bytes")
        continuation.yield(Data(buf.readableBytesView))
    }

    func channelInactive(context: ChannelHandlerContext) {
        log.info("[ShellHandler] channelInactive — finishing stream")
        continuation.finish()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        log.error("[ShellHandler] errorCaught: \(String(reflecting: error))")
        continuation.finish()
        context.close(promise: nil)
    }

    // Wrap outbound ByteBuffer writes as SSHChannelData before sending to the server.
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(
            wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))),
            promise: promise
        )
    }
}

// MARK: - SSH Transport State Handler

/// Tracks the parent SSH transport lifecycle so the caller can wait for
/// authentication before opening a child session channel.
private final class SSHTransportStateHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private let serverName: String
    private let authenticationPromise: EventLoopPromise<Void>
    private var authenticationResolved = false

    init(serverName: String, authenticationPromise: EventLoopPromise<Void>) {
        self.serverName = serverName
        self.authenticationPromise = authenticationPromise
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is UserAuthSuccessEvent:
            guard !authenticationResolved else { break }
            authenticationResolved = true
            log.info("[\(self.serverName)] SSH authentication succeeded")
            authenticationPromise.succeed(())

        case let banner as NIOUserAuthBannerEvent:
            log.info("[\(self.serverName)] SSH auth banner received: \(banner.message, privacy: .public)")

        default:
            break
        }

        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        failAuthenticationIfNeeded(SSHServiceError.connectionClosedBeforeAuthentication)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        log.error("[\(self.serverName)] SSH transport error: \(String(reflecting: error))")
        failAuthenticationIfNeeded(error)
        context.fireErrorCaught(error)
        context.close(promise: nil)
    }

    private func failAuthenticationIfNeeded(_ error: any Error) {
        guard !authenticationResolved else { return }
        authenticationResolved = true
        authenticationPromise.fail(error)
    }
}

// MARK: - Auth Delegates

private final class PasswordAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let password: String
    private var offered = false

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        log.info("[PasswordAuthDelegate] nextAuthenticationType called — available: \(String(describing: availableMethods)), offered=\(self.offered)")
        guard !offered else {
            log.error("[PasswordAuthDelegate] password authentication was rejected by the server")
            nextChallengePromise.fail(SSHServiceError.authenticationRejected(method: "password"))
            return
        }
        guard availableMethods.contains(.password) else {
            log.error("[PasswordAuthDelegate] server does not allow password auth; available=\(String(describing: availableMethods))")
            nextChallengePromise.fail(
                SSHServiceError.unsupportedAuthenticationMethod(
                    requested: "password",
                    available: availableMethods
                )
            )
            return
        }
        offered = true
        log.info("[PasswordAuthDelegate] offering password auth for user '\(self.username)'")
        nextChallengePromise.succeed(.init(
            username: username,
            serviceName: "",
            offer: .password(.init(password: password))
        ))
    }
}

/// Authenticates with an ED25519 private key stored as raw 32-byte CryptoKit representation.
private final class PrivateKeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let privateKeyData: Data
    private var offered = false

    init(username: String, privateKeyData: Data) {
        self.username = username
        self.privateKeyData = privateKeyData
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        log.info("[PrivateKeyAuthDelegate] nextAuthenticationType called — available: \(String(describing: availableMethods)), offered=\(self.offered)")
        guard !offered else {
            log.error("[PrivateKeyAuthDelegate] private key authentication was rejected by the server")
            nextChallengePromise.fail(SSHServiceError.authenticationRejected(method: "public key"))
            return
        }
        guard availableMethods.contains(.publicKey) else {
            log.error("[PrivateKeyAuthDelegate] server does not allow public key auth; available=\(String(describing: availableMethods))")
            nextChallengePromise.fail(
                SSHServiceError.unsupportedAuthenticationMethod(
                    requested: "public key",
                    available: availableMethods
                )
            )
            return
        }
        offered = true
        log.info("[PrivateKeyAuthDelegate] offering public key auth for user '\(self.username)'")
        do {
            let cryptoKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
            let sshKey = NIOSSHPrivateKey(ed25519Key: cryptoKey)
            nextChallengePromise.succeed(.init(
                username: username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: sshKey))
            ))
        } catch {
            log.error("[PrivateKeyAuthDelegate] key reconstruction failed: \(String(reflecting: error))")
            nextChallengePromise.fail(error)
        }
    }
}

/// Trust-on-first-connect host key pinning using NIOSSH's String(openSSHPublicKey:) as the stable fingerprint.
private final class TrustOnFirstConnectDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let verifier: SSHHostKeyVerifier

    init(host: String) {
        self.verifier = SSHHostKeyVerifier(host: host)
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        // String(openSSHPublicKey:) produces a stable "algorithm base64key" representation
        let fingerprint = String(openSSHPublicKey: hostKey)
        log.info("[HostKeyDelegate] validateHostKey called for host='\(self.verifier.host)' fingerprint prefix='\(fingerprint.prefix(30))…'")

        Task {
            do {
                try await self.verifier.validate(fingerprint: fingerprint)
                validationCompletePromise.succeed()
            } catch {
                log.error("[HostKeyDelegate] host key validation failed: \(String(reflecting: error))")
                validationCompletePromise.fail(error)
            }
        }
    }
}

private func authenticationMaterial(for target: SSHConnectionTarget) async throws -> SSHAuthenticationMaterial {
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
    private let backend: any SSHBackend

    init(backend: (any SSHBackend)? = nil) {
        self.backend = backend ?? SSHBackendFactory.makePreferredBackend()
    }

    private(set) var statuses: [UUID: ConnectionStatus] = [:]
    private(set) var sessions: [UUID: SSHSession] = [:]

    var backendKind: SSHBackendKind {
        backend.kind
    }

    var backendDisplayName: String {
        backend.kind.displayName
    }

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

    // MARK: Disconnect

    func disconnect(serverID: UUID) {
        sessions[serverID]?.close()
        sessions.removeValue(forKey: serverID)
        statuses[serverID] = .disconnected
    }
}

final class NIOSSHBackend: SSHBackend {
    let kind: SSHBackendKind = .nioSSH
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)

    func connect(to target: SSHConnectionTarget, initialTerminalSize: SSHTerminalSize) async throws -> SSHSession {
        log.info("[\(target.serverName)] Starting connection to \(target.host):\(target.port)")

        let authMaterial = try await authenticationMaterial(for: target)
        let authDelegate = try authDelegate(for: authMaterial)
        let sshConfig = SSHClientConfiguration(
            userAuthDelegate: authDelegate,
            serverAuthDelegate: TrustOnFirstConnectDelegate(host: target.host)
        )
        nonisolated(unsafe) let bootstrapSSHConfig = sshConfig

        final class AuthenticationPromiseBox {
            var promise: EventLoopPromise<Void>?
        }
        let authPromiseBox = AuthenticationPromiseBox()

        log.info("[\(target.serverName)] Bootstrapping TCP connection…")
        let tcpChannel: Channel
        do {
            tcpChannel = try await ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        let authenticationPromise = channel.eventLoop.makePromise(of: Void.self)
                        authPromiseBox.promise = authenticationPromise
                        try channel.pipeline.syncOperations.addHandlers([
                            NIOSSHHandler(
                                role: .client(bootstrapSSHConfig),
                                allocator: channel.allocator,
                                inboundChildChannelInitializer: nil
                            ),
                            SSHTransportStateHandler(
                                serverName: target.serverName,
                                authenticationPromise: authenticationPromise
                            ),
                        ])
                    }
                }
                .connectTimeout(.seconds(15))
                .connect(host: target.host, port: target.port)
                .get()
            log.info("[\(target.serverName)] TCP channel established: \(String(describing: tcpChannel))")
        } catch {
            log.error("[\(target.serverName)] TCP connect failed: \(String(reflecting: error))")
            throw error
        }

        guard let authenticationPromise = authPromiseBox.promise else {
            tcpChannel.close(promise: nil)
            throw SSHServiceError.connectionClosedBeforeAuthentication
        }

        log.info("[\(target.serverName)] Waiting for SSH authentication…")
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await authenticationPromise.futureResult.get()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw SSHServiceError.authenticationTimedOut
                }

                let result: Void? = try await group.next()
                group.cancelAll()
                if let result {
                    return result
                }
            }
            log.info("[\(target.serverName)] SSH transport is active")
        } catch {
            log.error("[\(target.serverName)] SSH authentication failed: \(String(reflecting: error))")
            tcpChannel.close(promise: nil)
            throw error
        }

        let (outputStream, outputContinuation) = AsyncStream<Data>.makeStream()

        log.info("[\(target.serverName)] Opening SSH shell channel…")
        let shellChannel: Channel
        do {
            shellChannel = try await openShellChannel(
                on: tcpChannel,
                outputContinuation: outputContinuation,
                initialTerminalSize: initialTerminalSize
            )
            log.info("[\(target.serverName)] Shell channel open: \(String(describing: shellChannel))")
        } catch {
            log.error("[\(target.serverName)] Shell channel failed: \(String(reflecting: error))")
            tcpChannel.close(promise: nil)
            throw error
        }

        log.info("[\(target.serverName)] Connection complete.")
        return SSHSession(
            serverID: target.serverID,
            serverName: target.serverName,
            backendKind: kind,
            transport: NIOSSHSessionTransport(tcpChannel: tcpChannel, shellChannel: shellChannel),
            outputStream: outputStream
        )
    }

    // MARK: - Shell Channel

    private func openShellChannel(
        on tcpChannel: Channel,
        outputContinuation: AsyncStream<Data>.Continuation,
        initialTerminalSize: SSHTerminalSize
    ) async throws -> Channel {
        log.info("[openShellChannel] looking up NIOSSHHandler in pipeline")
        // pipeline.handler(type:) returns an EventLoopFuture, so flatMap runs on the event loop.
        // This satisfies createChannel's requirement of only being called from on the channel.
        return try await tcpChannel.pipeline.handler(type: NIOSSHHandler.self).flatMap { sshHandler in
            log.info("[openShellChannel] found NIOSSHHandler — calling createChannel")
            let promise = tcpChannel.eventLoop.makePromise(of: Channel.self)
            sshHandler.createChannel(promise) { childChannel, channelType in
                log.info("[openShellChannel] childChannel initializer called, type=\(String(describing: channelType))")
                guard channelType == .session else {
                    log.error("[openShellChannel] unexpected channel type: \(String(describing: channelType))")
                    return childChannel.eventLoop.makeFailedFuture(SSHServiceError.unexpectedChannelType)
                }
                return childChannel.eventLoop.makeCompletedFuture {
                    log.info("[openShellChannel] adding ShellHandler to child pipeline")
                    try childChannel.pipeline.syncOperations.addHandler(
                        ShellHandler(outputContinuation, initialTerminalSize: initialTerminalSize)
                    )
                }
            }
            log.info("[openShellChannel] waiting on channel promise")
            return promise.futureResult
        }.get()
    }

    private func authDelegate(
        for material: SSHAuthenticationMaterial
    ) throws -> any NIOSSHClientUserAuthenticationDelegate {
        switch material {
        case .password(let username, let password):
            return PasswordAuthDelegate(username: username, password: password)
        case .privateKey(let username, let privateKeyData):
            return PrivateKeyAuthDelegate(username: username, privateKeyData: privateKeyData)
        }
    }

    func presentableError(from error: any Error) -> any Error {
        if error is SSHServiceError {
            return error
        }

        guard let sshError = error as? NIOSSHError else {
            return error
        }

        let message: String
        switch sshError.type {
        case .protocolViolation:
            message = "The SSH server and client disagreed on the protocol during setup."
        case .channelSetupRejected:
            message = "The SSH server rejected the session channel request."
        case .creatingChannelAfterClosure:
            message = "The SSH connection closed before a session channel could be created."
        case .keyExchangeNegotiationFailure:
            message = "The SSH client and server could not agree on a supported algorithm set."
        case .unsupportedVersion:
            message = "The SSH server is using an unsupported protocol version."
        case .tcpShutdown:
            message = "The TCP connection closed before SSH setup completed cleanly."
        default:
            message = String(describing: sshError)
        }

        return SSHServiceError.sshLibraryError(message)
    }
}

/// Placeholder for the libssh migration target. The app still defaults to
/// `NIOSSHBackend` until the C bridge and Xcode integration land.
final class LibsshBackend: SSHBackend {
    let kind: SSHBackendKind = .libssh

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
    case unsupportedAuthenticationMethod(requested: String, available: NIOSSHAvailableUserAuthenticationMethods)
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
        case .unsupportedAuthenticationMethod(let requested, let available):
            return "The server does not allow \(requested) authentication. Available methods: \(available.readableDescription)."
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

private extension NIOSSHAvailableUserAuthenticationMethods {
    var readableDescription: String {
        let knownMethods = [
            (Self.publicKey, "public key"),
            (Self.password, "password"),
            (Self.hostBased, "host based"),
        ]
        let names = knownMethods.compactMap { contains($0.0) ? $0.1 : nil }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }
}

// MARK: - NIOSSHPublicKey fingerprint helper

extension NIOSSHPublicKey {
    /// A stable, unique string representation suitable for host key pinning.
    var fingerprint: String {
        String(openSSHPublicKey: self)
    }
}
