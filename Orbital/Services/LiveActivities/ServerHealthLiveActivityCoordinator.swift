//
//  ServerHealthLiveActivityCoordinator.swift
//  Orbital
//
//  Created by Jonathan on 4/17/26.
//

import ActivityKit
import Foundation
import OSLog

@MainActor
final class ServerHealthLiveActivityCoordinator {
    private enum DefaultsKey {
        static let preferredServerID = "dynamicIsland.preferredServerID"
    }

    private let logger = Logger(subsystem: "com.orbital", category: "ServerHealthLiveActivity")
    private let defaults: UserDefaults

    private var activeActivity: Activity<ServerHealthActivityAttributes>?
    private var activeServerID: UUID?
    private var latestStateByServerID: [UUID: ServerHealthActivityAttributes.ContentState] = [:]
    private var latestServerNameByServerID: [UUID: String] = [:]
    private var staleTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferredServerID: UUID? {
        guard let rawValue = defaults.string(forKey: DefaultsKey.preferredServerID) else { return nil }
        return UUID(uuidString: rawValue)
    }

    func isPreferred(serverID: UUID) -> Bool {
        preferredServerID == serverID
    }

    func enable(for server: Server) {
        defaults.set(server.id.uuidString, forKey: DefaultsKey.preferredServerID)
        latestServerNameByServerID[server.id] = server.name

        if let activeServerID, activeServerID != server.id {
            Task {
                await endCurrentActivity(dismissalPolicy: .immediate)
            }
        }
    }

    func disable(for serverID: UUID) {
        guard preferredServerID == serverID else { return }
        defaults.removeObject(forKey: DefaultsKey.preferredServerID)

        guard activeServerID == serverID else { return }

        Task {
            await endCurrentActivity(dismissalPolicy: .immediate)
        }
    }

    func handleSnapshot(_ snapshot: MetricSnapshot, server: Server, pollingInterval: TimeInterval) {
        latestServerNameByServerID[server.id] = server.name
        let state = ServerHealthLiveActivitySupport.makeState(from: snapshot)
        latestStateByServerID[server.id] = state

        guard preferredServerID == server.id else { return }

        Task {
            await upsertActivity(for: server.id, serverName: server.name, state: state)
            scheduleStaleLifecycle(for: server.id, pollingInterval: pollingInterval)
        }
    }

    func handlePollingStopped(serverID: UUID, isManual: Bool, pollingInterval: TimeInterval?) {
        guard preferredServerID == serverID else { return }

        if isManual {
            defaults.removeObject(forKey: DefaultsKey.preferredServerID)

            guard activeServerID == serverID else { return }
            Task {
                await endCurrentActivity(dismissalPolicy: .immediate)
            }
            return
        }

        if let pollingInterval {
            scheduleStaleLifecycle(for: serverID, pollingInterval: pollingInterval)
        }
    }

    private func scheduleStaleLifecycle(for serverID: UUID, pollingInterval: TimeInterval) {
        staleTask?.cancel()

        let staleAfter = ServerHealthLiveActivitySupport.staleTimeout(for: pollingInterval)
        let dismissAfter = ServerHealthLiveActivitySupport.staleDismissDelay(for: pollingInterval)

        staleTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .seconds(staleAfter))
            } catch {
                return
            }

            await self.markActivityStaleIfNeeded(for: serverID)

            do {
                try await Task.sleep(for: .seconds(dismissAfter))
            } catch {
                return
            }

            guard self.activeServerID == serverID else { return }
            await self.endCurrentActivity(dismissalPolicy: .default)
        }
    }

    private func markActivityStaleIfNeeded(for serverID: UUID) async {
        guard activeServerID == serverID,
              let activeActivity,
              let existingState = latestStateByServerID[serverID] else {
            return
        }

        let staleState = ServerHealthLiveActivitySupport.makeStaleState(from: existingState, at: .now)
        latestStateByServerID[serverID] = staleState
        await activeActivity.update(ActivityContent(state: staleState, staleDate: nil))
    }

    private func upsertActivity(
        for serverID: UUID,
        serverName: String,
        state: ServerHealthActivityAttributes.ContentState
    ) async {
        if activeServerID == serverID, let activeActivity {
            await activeActivity.update(ActivityContent(state: state, staleDate: nil))
            return
        }

        if activeActivity != nil {
            await endCurrentActivity(dismissalPolicy: .immediate)
        }

        let attributes = ServerHealthActivityAttributes(serverID: serverID, serverName: serverName)

        do {
            activeActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            activeServerID = serverID
        } catch {
            logger.error("Failed to request Live Activity for \(serverName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func endCurrentActivity(dismissalPolicy: ActivityUIDismissalPolicy) async {
        staleTask?.cancel()
        staleTask = nil

        guard let activeActivity else {
            activeServerID = nil
            return
        }

        await activeActivity.end(nil, dismissalPolicy: dismissalPolicy)
        self.activeActivity = nil
        activeServerID = nil
    }
}
