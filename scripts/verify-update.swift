import Foundation
import CryptoKit

// Verify against the *bundled public key*, not merely the signer's private key.
// This prevents publishing a release signed by an accidentally replaced CI secret.
do {
    let args = CommandLine.arguments
    guard args.count == 4,
          let signature = Data(base64Encoded: args[2]),
          let keyData = Data(base64Encoded: args[3]) else {
        throw NSError(domain: "ReleaseVerification", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Usage: verify-update.swift archive signature public-key"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "ReleaseVerification", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Archive signature does not match the app's SUPublicEDKey"])
    }
    print("Ed25519 signature verified against bundled public key")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
