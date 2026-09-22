import Foundation
import Security
import Argon2Kit

enum PasswordError: Error {
    case randomFailed
}

public enum Password {
    // Same parameters the previous Rust build stored: Argon2id, m=19 MiB, t=2, p=1.
    private static let iterations: UInt32 = 2
    private static let memoryKiB: UInt32 = 19_456
    private static let threads: UInt32 = 1
    private static let length: UInt32 = 32
    private static let queue = DispatchQueue(label: "app.vigil.lock.argon2")

    public static func hash(_ password: String) throws -> String {
        var salt = [UInt8](repeating: 0, count: 16)
        let status = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 16, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw PasswordError.randomFailed }
        return try queue.sync {
            let digest = try Argon2.hash(
                password: password,
                salt: Data(salt),
                iterations: iterations,
                memory: memoryKiB,
                threads: threads,
                length: length,
                type: .id,
                version: .latest
            )
            return digest.encodedString
                .replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public static func verify(_ password: String, hash: String) -> Bool {
        queue.sync {
            (try? Argon2.verify(password: password, encodedHash: hash, type: .id)) ?? false
        }
    }
}
