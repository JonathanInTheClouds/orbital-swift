//
//  BiometricService.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

internal import LocalAuthentication

actor BiometricService {
    static let shared = BiometricService()
    private init() {}

    nonisolated var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    nonisolated var isAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Returns true if authentication succeeded, throws on failure or unavailability.
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            throw policyError ?? BiometricError.notAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

enum BiometricError: LocalizedError {
    case notAvailable

    var errorDescription: String? {
        "Biometric authentication is not available on this device."
    }
}
