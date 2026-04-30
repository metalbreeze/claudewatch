import Foundation

public protocol KeychainStoring {
    func read(service: String, account: String) throws -> Data?
    func write(service: String, account: String, data: Data) throws
    func delete(service: String, account: String) throws
}

public enum DeviceID {
    public static let service = "com.claudeusage.deviceid"
    public static let account = "device-uuid"

    public static func getOrCreate(in store: KeychainStoring) throws -> String {
        if let d = try store.read(service: service, account: account),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        let new = UUID().uuidString
        try store.write(service: service, account: account, data: Data(new.utf8))
        return new
    }
}
