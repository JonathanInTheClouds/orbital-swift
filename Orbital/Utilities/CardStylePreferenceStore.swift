//
//  CardStylePreferenceStore.swift
//  Orbital
//
//  Created by Codex on 4/16/26.
//

import Foundation

enum CardStylePreferenceStore {
    static func read(from serialized: String) -> [String: String] {
        guard let data = serialized.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return decoded
    }

    static func write(_ preferences: [String: String]) -> String {
        guard !preferences.isEmpty,
              let data = try? JSONEncoder().encode(preferences),
              let serialized = String(data: data, encoding: .utf8) else {
            return ""
        }

        return serialized
    }
}
