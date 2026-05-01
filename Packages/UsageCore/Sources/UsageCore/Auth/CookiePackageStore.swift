import Foundation

public struct CookiePackageStore {
    public static let service = "studio.cybertron.claudewatch.cookie"
    let keychain: KeychainStoring
    let deviceID: String
    public init(keychain: KeychainStoring, deviceID: String) {
        self.keychain = keychain; self.deviceID = deviceID
    }

    public func save(_ pkg: CookiePackage) throws {
        let data = try JSONEncoder().encode(pkg)
        try keychain.write(service: Self.service, account: deviceID, data: data)
    }
    public func load() throws -> CookiePackage? {
        guard let d = try keychain.read(service: Self.service, account: deviceID) else { return nil }
        return try JSONDecoder().decode(CookiePackage.self, from: d)
    }
    public func clear() throws {
        try keychain.delete(service: Self.service, account: deviceID)
    }
}
