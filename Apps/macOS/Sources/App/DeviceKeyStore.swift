import Foundation

/// Remembers ES100 authorization without accessing the user's Keychain.
/// The app's single-instance guard serializes access to this local store.
struct DeviceKeyStore {
    static let shared = DeviceKeyStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("EarStudioCompanion", isDirectory: true))

    private let directory: URL
    private var file: URL { directory.appendingPathComponent("device-keys.json") }

    init(directory: URL) { self.directory = directory }

    func read(_ address: String) -> UInt16 {
        guard !address.isEmpty else { return 0 }
        return (try? load()[address]) ?? 0
    }

    @discardableResult
    func save(_ key: UInt16, for address: String) -> Bool {
        guard !address.isEmpty else { return false }
        do {
            var keys = try load()
            let manager = FileManager.default
            // Restrict the directory before writing: even the temporary file
            // used by an atomic replacement is inaccessible to other users.
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if manager.fileExists(atPath: file.path) {
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
            guard keys[address] != key else { return true }
            keys[address] = key
            try write(keys)
            return true
        } catch { return false }
    }

    @discardableResult
    func forget(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        do {
            var keys = try load()
            guard keys.removeValue(forKey: address) != nil else { return true }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try write(keys)
            return true
        } catch { return false }
    }

    private func load() throws -> [String: UInt16] {
        do {
            return try JSONDecoder().decode([String: UInt16].self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        }
        // Other read/decode failures propagate so saving cannot overwrite an
        // unreadable or damaged file and discard other devices' tokens.
    }

    private func write(_ keys: [String: UInt16]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(keys).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
