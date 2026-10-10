#if !SWIFT_PACKAGE
import XCTest
import IOBluetooth
@testable import EarStudioCompanion

final class DeviceKeyStoreTests: XCTestCase {
    private var root: URL!
    private var directory: URL { root.appendingPathComponent("EarStudioCompanion") }
    private var file: URL { directory.appendingPathComponent("device-keys.json") }
    private var store: DeviceKeyStore { DeviceKeyStore(directory: directory) }
    private let firstAddress = "AA:BB:CC:DD:EE:01"
    private let secondAddress = "AA:BB:CC:DD:EE:02"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testMissingStoreUsesInitialConfirmationWithoutCreatingFiles() {
        XCTAssertEqual(store.read(firstAddress), 0)
        XCTAssertTrue(store.forget(firstAddress))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(store.save(0x1234, for: ""))
        XCTAssertFalse(store.forget(""))
    }

    func testKeysSurviveRelaunchAndUpdatesPreserveOtherDevices() {
        XCTAssertTrue(store.save(0x1234, for: firstAddress))
        XCTAssertTrue(store.save(0xABCD, for: secondAddress))
        // Every access uses a new instance, as on a later app launch.
        XCTAssertEqual(store.read(firstAddress), 0x1234)
        XCTAssertEqual(store.read(secondAddress), 0xABCD)
        XCTAssertTrue(store.save(UInt16.max, for: firstAddress))
        XCTAssertEqual(store.read(firstAddress), UInt16.max)
        XCTAssertEqual(store.read(secondAddress), 0xABCD)
    }

    func testDirectoryAndFileAreRestrictedToCurrentUserAfterReplacement() throws {
        XCTAssertTrue(store.save(0x1234, for: firstAddress))
        try assertPrivatePermissions()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertTrue(store.save(0x1234, for: firstAddress)) // unchanged key still repairs permissions
        try assertPrivatePermissions()
        XCTAssertTrue(store.save(0x5678, for: firstAddress))
        try assertPrivatePermissions()
        XCTAssertTrue(store.forget(firstAddress))
        try assertPrivatePermissions()
    }

    func testUnchangedKeyDoesNotRewriteFile() throws {
        XCTAssertTrue(store.save(0x1234, for: firstAddress))
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
        let original = try Data(contentsOf: file)
        XCTAssertTrue(store.save(0x1234, for: firstAddress))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, oldDate)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testForgetRemovesOnlySelectedDeviceAndPersistsRemoval() {
        XCTAssertTrue(store.save(0x1234, for: firstAddress))
        XCTAssertTrue(store.save(0xABCD, for: secondAddress))
        XCTAssertTrue(store.forget(firstAddress))
        XCTAssertEqual(store.read(firstAddress), 0)
        XCTAssertEqual(store.read(secondAddress), 0xABCD)
        XCTAssertTrue(store.forget(firstAddress))
        XCTAssertTrue(store.forget(secondAddress))
        XCTAssertEqual(store.read(secondAddress), 0)
    }

    func testDamagedAndOutOfRangeFilesAreNotOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for invalid in ["invalid json", "{\"AA:BB:CC:DD:EE:01\":65536}"] {
            let original = Data(invalid.utf8)
            try original.write(to: file)
            XCTAssertEqual(store.read(firstAddress), 0)
            XCTAssertFalse(store.save(0x1234, for: firstAddress))
            XCTAssertFalse(store.forget(firstAddress))
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    func testUnavailableDirectoryReportsSaveFailure() throws {
        try Data("not a directory".utf8).write(to: directory)
        XCTAssertEqual(store.read(firstAddress), 0)
        XCTAssertFalse(store.save(0x1234, for: firstAddress))
        XCTAssertEqual(try Data(contentsOf: directory), Data("not a directory".utf8))
    }

    func testConnectionEnrollsThenReusesLocalKeyAndForgetResetsAuthentication() {
        let firstLink = KeyStoreTestTransport()
        let first = connectedModel(firstLink)
        firstLink.onOpen?()
        XCTAssertEqual(firstLink.sent.first, DeviceCommand.authenticate.packet([0, 0]).encoded())
        firstLink.onData?(GAIAPacket(command: 0x8303, payload: [0, 0x12, 0x34]).encoded())
        XCTAssertEqual(store.read(firstAddress), 0x1234)
        XCTAssertNil(first.message)
        first.disconnect()

        let secondLink = KeyStoreTestTransport()
        let second = connectedModel(secondLink)
        secondLink.onOpen?()
        XCTAssertEqual(secondLink.sent.first, DeviceCommand.authenticate.packet([0x12, 0x34]).encoded())
        second.forgetKey()
        XCTAssertEqual(second.phase, .disconnected)
        XCTAssertEqual(store.read(firstAddress), 0)

        let thirdLink = KeyStoreTestTransport()
        let third = connectedModel(thirdLink)
        defer { third.disconnect() }
        thirdLink.onOpen?()
        XCTAssertEqual(thirdLink.sent.first, DeviceCommand.authenticate.packet([0, 0]).encoded())
    }

    func testFailedSaveKeepsConnectionAndExplainsNextConfirmation() throws {
        try Data("not a directory".utf8).write(to: directory)
        let link = KeyStoreTestTransport()
        let model = connectedModel(link)
        defer { model.disconnect() }
        link.onOpen?()
        link.onData?(GAIAPacket(command: 0x8303, payload: [0, 0x12, 0x34]).encoded())
        XCTAssertEqual(model.phase, .syncing)
        XCTAssertTrue(model.message?.contains("could not be saved") == true)
        XCTAssertFalse(model.message?.contains("Keychain") == true)
    }

    func testFailedForgetDoesNotClaimConfirmationWasRemoved() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid json".utf8).write(to: file)
        let model = connectedModel(KeyStoreTestTransport())
        defer { model.disconnect() }
        model.forgetKey()
        XCTAssertEqual(model.phase, .connecting)
        XCTAssertEqual(model.message, "Could not remove the saved device confirmation. Please try again.")
    }

    private func assertPrivatePermissions(file source: StaticString = #filePath, line: UInt = #line) throws {
        for (url, expected) in [(directory, 0o700), (self.file, 0o600)] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
            XCTAssertEqual(permissions.intValue & 0o777, expected, file: source, line: line)
        }
    }

    private func connectedModel(_ link: KeyStoreTestTransport) -> StudioModel {
        let store = self.store
        let model = StudioModel(makeTransport: { link },
                                saveDeviceKey: { store.save($0, for: $1) },
                                readDeviceKey: { store.read($0) },
                                forgetDeviceKey: { store.forget($0) })
        let device = BluetoothTestObjects.keep(KeyStoreTestDevice())
        model.connect(DiscoveredDevice(device: device))
        let opened = expectation(description: "Connection callbacks installed")
        DispatchQueue.main.async { opened.fulfill() }
        wait(for: [opened], timeout: 1)
        return model
    }
}

private final class KeyStoreTestDevice: IOBluetoothDevice {
    override var addressString: String! { "AA:BB:CC:DD:EE:01" }
}

private final class KeyStoreTestTransport: ControlTransport {
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((TransportFailure) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var sent: [Data] = []

    func connect(_ target: IOBluetoothDevice) {}
    func send(_ data: Data) -> Bool { sent.append(data); return true }
    func close(completion: @escaping () -> Void) { completion() }
}
#endif
