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

// MARK: - SSH Session

/// A live SSH shell session. Owns the NIO channels and exposes an output stream for the terminal UI.
final class SSHSession: Identifiable {
    let id: UUID = UUID()
    let serverID: UUID
    let serverName: String

    /// Raw bytes arriving from the remote shell. Finishes when the connection drops.
    let outputStream: AsyncStream<Data>

    private let tcpChannel: Channel
    private let shellChannel: Channel

    init(
        serverID: UUID,
        serverName: String,
        tcpChannel: Channel,
        shellChannel: Channel,
        outputStream: AsyncStream<Data>
    ) {
        self.serverID = serverID
        self.serverName = serverName
        self.tcpChannel = tcpChannel
        self.shellChannel = shellChannel
        self.outputStream = outputStream
    }

    /// Send raw input bytes to the remote shell (keyboard input, paste, etc.).
    /// The `ShellHandler` in the pipeline wraps the ByteBuffer as SSHChannelData before sending.
    func write(_ data: Data) {
        var buffer = shellChannel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        shellChannel.writeAndFlush(buffer, promise: nil)
    }

    /// Close the shell and underlying TCP connection.
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

    init(_ continuation: AsyncStream<Data>.Continuation) {
        self.continuation = continuation
    }

    // Request a PTY then a shell as soon as the child channel becomes active.
    func channelActive(context: ChannelHandlerContext) {
        log.info("[ShellHandler] channelActive — requesting PTY then shell")

        // 1. Allocate a pseudo-terminal so the server opens a proper interactive shell.
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: 80,
            terminalRowHeight: 24,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
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
        guard !offered, availableMethods.contains(.password) else {
            log.warning("[PasswordAuthDelegate] not offering — offered=\(self.offered), hasPassword=\(availableMethods.contains(.password))")
            nextChallengePromise.succeed(nil)
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
        guard !offered, availableMethods.contains(.publicKey) else {
            log.warning("[PrivateKeyAuthDelegate] not offering — offered=\(self.offered), hasPublicKey=\(availableMethods.contains(.publicKey))")
            nextChallengePromise.succeed(nil)
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
    private let keychainKey: String

    init(host: String) {
        self.keychainKey = "hostkey:\(host)"
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        // String(openSSHPublicKey:) produces a stable "algorithm base64key" representation
        let fingerprint = String(openSSHPublicKey: hostKey)
        let keychainKey = self.keychainKey
        log.info("[HostKeyDelegate] validateHostKey called for keychainKey='\(keychainKey)' fingerprint prefix='\(fingerprint.prefix(30))…'")

        Task {
            let stored = await KeychainService.shared.loadIfPresent(key: keychainKey)
                .flatMap { String(data: $0, encoding: .utf8) }

            if let stored {
                if stored == fingerprint {
                    log.info("[HostKeyDelegate] fingerprint matches stored key — accepting")
                    validationCompletePromise.succeed()
                } else {
                    log.error("[HostKeyDelegate] fingerprint MISMATCH — rejecting connection")
                    validationCompletePromise.fail(SSHServiceError.hostKeyMismatch)
                }
            } else {
                log.info("[HostKeyDelegate] no stored key — trusting on first connect and saving")
                guard let data = fingerprint.data(using: .utf8) else {
                    validationCompletePromise.fail(SSHServiceError.hostKeyMismatch)
                    return
                }
                try? await KeychainService.shared.save(key: keychainKey, data: data)
                validationCompletePromise.succeed()
            }
        }
    }
}

// MARK: - SSH Service

@Observable
@MainActor
final class SSHService {
    static let shared = SSHService()
    private init() {}

    private(set) var statuses: [UUID: ConnectionStatus] = [:]
    private(set) var sessions: [UUID: SSHSession] = [:]

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)

    func status(for serverID: UUID) -> ConnectionStatus {
        statuses[serverID] ?? .disconnected
    }

    func session(for serverID: UUID) -> SSHSession? {
        sessions[serverID]
    }

    // MARK: Connect

    func connect(to server: Server) async throws -> SSHSession {
        statuses[server.id] = .connecting
        do {
            let session = try await _connect(to: server)
            sessions[server.id] = session
            statuses[server.id] = .connected
            return session
        } catch {
            statuses[server.id] = .error(error.localizedDescription)
            throw error
        }
    }

    private func _connect(to server: Server) async throws -> SSHSession {
        log.info("[\(server.name)] Starting connection to \(server.host):\(server.port)")

        // 1. Build the appropriate auth delegate from the stored credential
        let authDelegate: any NIOSSHClientUserAuthenticationDelegate

        switch server.authMethod {
        case .password:
            log.debug("[\(server.name)] Auth method: password, user=\(server.username)")
            let password: String
            if server.credentialRef.isEmpty {
                log.warning("[\(server.name)] credentialRef is empty — connecting with empty password")
                password = ""
            } else {
                password = try await KeychainService.shared.loadString(key: server.credentialRef)
                log.debug("[\(server.name)] Loaded password credential from Keychain")
            }
            authDelegate = PasswordAuthDelegate(username: server.username, password: password)

        case .privateKey:
            log.debug("[\(server.name)] Auth method: privateKey, user=\(server.username)")
            let keyData = try await KeychainService.shared.load(key: server.credentialRef)
            log.debug("[\(server.name)] Loaded \(keyData.count)-byte key from Keychain")
            authDelegate = PrivateKeyAuthDelegate(username: server.username, privateKeyData: keyData)
        }

        // 2. Connect TCP + SSH handshake
        let sshConfig = SSHClientConfiguration(
            userAuthDelegate: authDelegate,
            serverAuthDelegate: TrustOnFirstConnectDelegate(host: server.host)
        )

        log.info("[\(server.name)] Bootstrapping TCP connection…")
        let tcpChannel: Channel
        do {
            tcpChannel = try await ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandlers([
                            NIOSSHHandler(
                                role: .client(sshConfig),
                                allocator: channel.allocator,
                                inboundChildChannelInitializer: nil
                            )
                        ])
                    }
                }
                .connectTimeout(.seconds(15))
                .connect(host: server.host, port: server.port)
                .get()
            log.info("[\(server.name)] TCP channel established: \(String(describing: tcpChannel))")
        } catch {
            log.error("[\(server.name)] TCP connect failed: \(String(reflecting: error))")
            throw error
        }

        // 3. Build the output pipe before opening the shell channel
        let (outputStream, outputContinuation) = AsyncStream<Data>.makeStream()

        // 4. Open shell channel; ShellHandler takes ownership of the continuation
        log.info("[\(server.name)] Opening SSH shell channel…")
        let shellChannel: Channel
        do {
            shellChannel = try await openShellChannel(
                on: tcpChannel,
                outputContinuation: outputContinuation
            )
            log.info("[\(server.name)] Shell channel open: \(String(describing: shellChannel))")
        } catch {
            log.error("[\(server.name)] Shell channel failed: \(String(reflecting: error))")
            tcpChannel.close(promise: nil)
            throw error
        }

        log.info("[\(server.name)] Connection complete.")
        return SSHSession(
            serverID: server.id,
            serverName: server.name,
            tcpChannel: tcpChannel,
            shellChannel: shellChannel,
            outputStream: outputStream
        )
    }

    // MARK: Disconnect

    func disconnect(serverID: UUID) {
        sessions[serverID]?.close()
        sessions.removeValue(forKey: serverID)
        statuses[serverID] = .disconnected
    }

    // MARK: - Shell Channel

    private func openShellChannel(
        on tcpChannel: Channel,
        outputContinuation: AsyncStream<Data>.Continuation
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
                        ShellHandler(outputContinuation)
                    )
                }
            }
            log.info("[openShellChannel] waiting on channel promise")
            return promise.futureResult
        }.get()
    }
}

// MARK: - Errors

enum SSHServiceError: LocalizedError {
    case hostKeyMismatch
    case unexpectedChannelType
    case noCredential

    var errorDescription: String? {
        switch self {
        case .hostKeyMismatch:
            return "The server's host key has changed. Remove the stored key in Settings to reconnect."
        case .unexpectedChannelType:
            return "Unexpected SSH channel type received."
        case .noCredential:
            return "No credential is stored for this server."
        }
    }
}

// MARK: - NIOSSHPublicKey fingerprint helper

extension NIOSSHPublicKey {
    /// A stable, unique string representation suitable for host key pinning.
    var fingerprint: String {
        String(openSSHPublicKey: self)
    }
}
