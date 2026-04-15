//
//  SSHPublicKeyEncoder.swift
//  Orbital
//
//  Created by Jonathan on 4/15/26.
//

import Crypto
import Foundation

/// Encodes an Orbital-generated ED25519 key (stored as a 32-byte raw seed) into the
/// OpenSSH authorized_keys wire format: `ssh-ed25519 <base64blob> orbital`
///
/// Returns `nil` for imported PEM keys or any data that isn't a valid 32-byte ED25519 seed.
func sshPublicKeyString(fromRawEd25519Seed seed: Data) -> String? {
    guard seed.count == 32,
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    else { return nil }

    let pub = Data(key.publicKey.rawRepresentation)
    var blob = Data()

    // Length-prefixed algorithm name
    var algLen = UInt32("ssh-ed25519".utf8.count).bigEndian
    withUnsafeBytes(of: &algLen) { blob.append(contentsOf: $0) }
    blob.append(Data("ssh-ed25519".utf8))

    // Length-prefixed public key bytes
    var keyLen = UInt32(pub.count).bigEndian
    withUnsafeBytes(of: &keyLen) { blob.append(contentsOf: $0) }
    blob.append(pub)

    return "ssh-ed25519 \(blob.base64EncodedString()) orbital"
}
