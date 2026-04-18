//
//  ContainerRuntimeShell.swift
//  Orbital
//
//  Created by Jonathan on 4/18/26.
//

import Foundation

func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
}

func shellCommandWithContainerRuntimePath(_ command: String) -> String {
    "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"; \(command)"
}
