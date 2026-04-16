//
//  Server.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Foundation
import SwiftData

enum ServerOSKind: String, Codable, CaseIterable, Sendable {
    case unknown
    case linux
    case darwin

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .linux:   return "Linux"
        case .darwin:  return "macOS"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .linux:   return "server.rack"
        case .darwin:  return "apple.logo"
        }
    }
}

enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case password = "password"
    case privateKey = "privateKey"

    var displayName: String {
        switch self {
        case .password: return "Password"
        case .privateKey: return "Private Key"
        }
    }
}

enum VolumeSelectionMode: String, Codable, CaseIterable, Sendable {
    case all
    case custom
}

@Model
final class Server {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    /// Keychain reference key under which the credential is stored
    var credentialRef: String
    var jumpHostRef: String?
    var tags: [String]
    var notes: String
    /// Named color used to accent the card (e.g. "blue", "green", "red")
    var colorTag: String
    var volumeSelectionMode: VolumeSelectionMode
    var selectedVolumeMountPoints: [String]
    var detailSectionOrder: [String]
    var metricsSectionOrder: [String]
    /// Detected OS; populated automatically on the first successful metrics poll
    var osKind: ServerOSKind
    var createdAt: Date
    var lastSeenAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .password,
        credentialRef: String = "",
        jumpHostRef: String? = nil,
        tags: [String] = [],
        notes: String = "",
        colorTag: String = "blue",
        volumeSelectionMode: VolumeSelectionMode = .all,
        selectedVolumeMountPoints: [String] = [],
        detailSectionOrder: [String] = ["metrics", "connection", "details", "monitoring", "actions"],
        metricsSectionOrder: [String] = ["overview", "vitals", "history", "containers", "system", "disks"],
        osKind: ServerOSKind = .unknown,
        createdAt: Date = Date(),
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.credentialRef = credentialRef
        self.jumpHostRef = jumpHostRef
        self.tags = tags
        self.notes = notes
        self.colorTag = colorTag
        self.volumeSelectionMode = volumeSelectionMode
        self.selectedVolumeMountPoints = selectedVolumeMountPoints
        self.detailSectionOrder = detailSectionOrder
        self.metricsSectionOrder = metricsSectionOrder
        self.osKind = osKind
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}
