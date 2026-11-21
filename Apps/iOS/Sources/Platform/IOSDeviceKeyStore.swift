import Foundation
import Security

/// Each iPhone keeps its own ES100 authorization. Tokens never sync through
/// iCloud and remain available only while the device is unlocked.
struct IOSDeviceKeyStore {
    private let service = "com.igor.earstudio-companion.ios.device-authorization"

    func read(_ identifier: String) -> UInt16 {
        guard !identifier.isEmpty else { return 0 }
        var query = item(identifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let bytes = result as? Data, bytes.count == 2 else { return 0 }
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    func save(_ key: UInt16, for identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        let data = Data([UInt8(key >> 8), UInt8(key & 255)])
        let attributes: [String: Any] = [kSecValueData as String: data,
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let query = item(identifier)
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }

    func forget(_ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        let result = SecItemDelete(item(identifier) as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }

    private func item(_ identifier: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: identifier,
         kSecAttrSynchronizable as String: false]
    }
}
