//
//  Server.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Foundation
import SwiftData

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
    var detailSectionOrder: [String]
    var metricsSectionOrder: [String]
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
        detailSectionOrder: [String] = ["metrics", "connection", "details", "monitoring", "actions"],
        metricsSectionOrder: [String] = ["overview", "vitals", "history", "system", "disks"],
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
        self.detailSectionOrder = detailSectionOrder
        self.metricsSectionOrder = metricsSectionOrder
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}
