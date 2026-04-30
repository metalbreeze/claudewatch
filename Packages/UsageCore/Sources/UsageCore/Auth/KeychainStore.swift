import Foundation
import Security

public struct KeychainStore: KeychainStoring {
    public init() {}

    public func read(service: String, account: String) throws -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &item)
        switch s {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.osStatus(s)
        }
    }

    public func write(service: String, account: String, data: Data) throws {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let s = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if s == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = data
            let a = SecItemAdd(add as CFDictionary, nil)
            if a != errSecSuccess { throw KeychainError.osStatus(a) }
        } else if s != errSecSuccess {
            throw KeychainError.osStatus(s)
        }
    }

    public func delete(service: String, account: String) throws {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let s = SecItemDelete(q as CFDictionary)
        if s != errSecSuccess && s != errSecItemNotFound {
            throw KeychainError.osStatus(s)
        }
    }
}

public enum KeychainError: Error { case osStatus(OSStatus) }
