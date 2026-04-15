//
//  SSHCommandPool.swift
//  Orbital
//
//  Created by Codex on 4/14/26.
//

import Foundation
import OSLog

actor SSHCommandPool {
    private static let log = Logger(subsystem: "com.orbital", category: "SSHCommandPool")
    private var connections: [UUID: any SSHCommandTransport] = [:]

    func run(
        command: String,
        on target: SSHConnectionTarget,
        using backend: any SSHBackend
    ) async throws -> SSHCommandResult {
        if let connection = connections[target.serverID] {
            do {
                return try await connection.run(command: command)
            } catch {
                Self.log.error("[\(target.serverName)] Cached command connection failed; reconnecting: \(error.localizedDescription, privacy: .public)")
                await connection.close()
                connections.removeValue(forKey: target.serverID)
            }
        }

        let connection = try await backend.makeCommandTransport(to: target)
        connections[target.serverID] = connection

        do {
            return try await connection.run(command: command)
        } catch {
            Self.log.error("[\(target.serverName)] Command execution failed on a fresh connection; retrying once: \(error.localizedDescription, privacy: .public)")
            await connection.close()
            connections.removeValue(forKey: target.serverID)

            let retryConnection = try await backend.makeCommandTransport(to: target)
            connections[target.serverID] = retryConnection

            do {
                return try await retryConnection.run(command: command)
            } catch {
                await retryConnection.close()
                connections.removeValue(forKey: target.serverID)
                throw error
            }
        }
    }

    func disconnect(serverID: UUID) async {
        guard let connection = connections.removeValue(forKey: serverID) else { return }
        await connection.close()
    }

    func disconnectAll() async {
        let activeConnections = Array(connections.values)
        connections.removeAll()
        for connection in activeConnections {
            await connection.close()
        }
    }
}
