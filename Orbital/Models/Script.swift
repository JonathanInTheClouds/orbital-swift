//
//  Script.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Foundation
import SwiftData

/// A reusable shell script (Phase 3 — model stub)
@Model
final class Script {
    var id: UUID
    var name: String
    var body: String
    var language: String
    var parameters: [String]
    var folder: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        body: String = "",
        language: String = "bash",
        parameters: [String] = [],
        folder: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.language = language
        self.parameters = parameters
        self.folder = folder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
