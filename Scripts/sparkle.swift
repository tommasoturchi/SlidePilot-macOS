// Manages the EdDSA key, which signs SlidePilot updates for Sparkle.
//
// The private key is kept in the login keychain, in the same item that Sparkle's own tools
// (generate_keys, sign_update) use, so they can be used instead of this script.
//
// Run from the repository root:
//   swift Scripts/sparkle.swift key            Prints the public key, creating the key pair on first use
//   swift Scripts/sparkle.swift sign <file>    Prints the EdDSA signature of an update archive

import CryptoKit
import Foundation
import Security

let service = "https://sparkle-project.org"
let account = "ed25519"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

/** Returns the private key from the keychain, or nil if there is none yet. */
func storedPrivateKey() -> Curve25519.Signing.PrivateKey? {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
        return nil
    }
    guard status == errSecSuccess else { fail("Couldn't read the key from the keychain (\(status)).") }

    // The item holds the base64 encoded 32 byte seed of the key
    guard let data = result as? Data,
          let seed = Data(base64Encoded: data),
          seed.count == 32,
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
        fail("The keychain holds a Sparkle key in an older format. Use Sparkle's sign_update tool to sign updates.")
    }
    return key
}


func createPrivateKey() -> Curve25519.Signing.PrivateKey {
    let key = Curve25519.Signing.PrivateKey()
    let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: service,
                               kSecAttrAccount as String: account,
                               kSecAttrLabel as String: "Private key for signing Sparkle updates",
                               kSecValueData as String: key.rawRepresentation.base64EncodedData()]
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { fail("Couldn't save the key in the keychain (\(status)).") }
    return key
}


let arguments = CommandLine.arguments.dropFirst()

switch (arguments.first, arguments.count) {
case ("key", 1):
    let key = storedPrivateKey() ?? createPrivateKey()
    print(key.publicKey.rawRepresentation.base64EncodedString())

case ("sign", 2):
    guard let key = storedPrivateKey() else { fail("There is no key yet. Create it with: swift Scripts/sparkle.swift key") }
    guard let archive = FileManager.default.contents(atPath: arguments.last!) else { fail("Couldn't read \(arguments.last!).") }
    print(try key.signature(for: archive).base64EncodedString())

default:
    fail("Usage: swift Scripts/sparkle.swift key | sign <file>")
}
