//
//  ScriptRun.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Foundation
import SwiftData

/// A single execution record for a Script (Phase 3 — model stub)
@Model
final class ScriptRun {
    var id: UUID
    var script: Script?
    var targetServerID: UUID?
    var targetContainerID: String?
    var startedAt: Date
    var finishedAt: Date?
    var exitCode: Int?
    var outputSnapshot: String

    init(
        id: UUID = UUID(),
        script: Script? = nil,
        targetServerID: UUID? = nil,
        targetContainerID: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        exitCode: Int? = nil,
        outputSnapshot: String = ""
    ) {
        self.id = id
        self.script = script
        self.targetServerID = targetServerID
        self.targetContainerID = targetContainerID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.outputSnapshot = outputSnapshot
    }
}
