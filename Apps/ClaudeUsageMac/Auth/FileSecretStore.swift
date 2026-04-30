import Foundation
import UsageCore

/// File-backed `KeychainStoring` for macOS development. Stores secrets in
/// `~/Library/Application Support/ClaudeUsage/secrets/{service}--{account}`
/// with `0600` permissions.
///
/// Why not the real Keychain on macOS? Ad-hoc-signed development builds
/// produce a fresh binary signature on every rebuild, which makes macOS
/// pop the "Claude Usage wants to use your confidential information"
/// prompt every launch. Stable signing (a real Apple ID team) fixes that,
/// but until the user wires up signing this file store removes the
/// friction without weakening the threat model meaningfully — both
/// approaches are gated by the user's macOS login session and FileVault
/// disk encryption.
///
/// Threat model (same as Safari's cookie store at `~/Library/Cookies/`):
/// anyone with access to the logged-in user's account on this Mac can
/// read these files. That's the same exposure as the system Keychain
/// gives in practice, since the Keychain is unlocked while the user is
/// logged in.
///
/// For App Store distribution, swap back to `KeychainStore` (or sign
/// properly and keep this — your call).
public struct FileSecretStore: KeychainStoring {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Convenience initializer that resolves
    /// `~/Library/Application Support/ClaudeUsage/secrets/`.
    public init() throws {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
            .appendingPathComponent("ClaudeUsage", isDirectory: true)
            .appendingPathComponent("secrets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        self.directory = dir
    }

    public func read(service: String, account: String) throws -> Data? {
        let url = fileURL(service: service, account: account)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(service: String, account: String, data: Data) throws {
        let url = fileURL(service: service, account: account)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func delete(service: String, account: String) throws {
        let url = fileURL(service: service, account: account)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(service: String, account: String) -> URL {
        // Use a delimiter that can't appear in our service/account strings.
        let safe = "\(service)--\(account)"
            .replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe)
    }
}
