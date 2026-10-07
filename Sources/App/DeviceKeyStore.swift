import Foundation
import Security

enum DeviceKeyStore {
    private static func query(_ address: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "EarStudioCompanion.DeviceAuthentication",
         kSecAttrAccount as String: address]
    }
    static func read(_ address: String) -> UInt16 {
        var q = query(address)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 2 else { return 0 }
        return Wire.readU16(Array(data), 0)
    }
    @discardableResult
    static func save(_ key: UInt16, for address: String) -> Bool {
        let q = query(address), data = Data(Wire.u16(key))
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
    static func forget(_ address: String) { SecItemDelete(query(address) as CFDictionary) }
}
