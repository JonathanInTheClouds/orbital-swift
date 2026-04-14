//
//  KeychainService.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import Foundation
import Security

actor KeychainService {
    static let shared = KeychainService()
    private init() {}

    // MARK: - Save

    func save(key: String, data: Data) throws {
        // Delete any existing item first to allow overwrites
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func saveString(_ string: String, key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(key: key, data: data)
    }

    // MARK: - Load

    func load(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return data
    }

    func loadString(key: String) throws -> String {
        let data = try load(key: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return string
    }

    func loadIfPresent(key: String) -> Data? {
        try? load(key: key)
    }

    // MARK: - Delete

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Enumerate

    func allKeys() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw KeychainError.loadFailed(status)
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

// MARK: - Error

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed (OSStatus \(s))"
        case .loadFailed(let s): return "Keychain load failed (OSStatus \(s))"
        case .deleteFailed(let s): return "Keychain delete failed (OSStatus \(s))"
        case .encodingFailed: return "String encoding failed"
        }
    }
}
