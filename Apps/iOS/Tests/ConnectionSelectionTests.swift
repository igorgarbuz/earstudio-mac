import XCTest
import EarStudioSession
@testable import EarStudioIOS

@MainActor
final class ConnectionSelectionTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var model: IOSStudioModel!
    private var attempted: [UUID] = []
    private var scans = 0

    override func setUp() {
        super.setUp()
        suite = "ConnectionSelectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        model?.cancelConnection()
        model?.disconnect()
        model = nil
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeModel(remembering device: IOSDevice? = nil) throws {
        if let device {
            defaults.set(try JSONEncoder().encode(device), forKey: "lastConnectedEarStudio")
        }
        model = IOSStudioModel(defaults: defaults, makeTransport: { [weak self] id in
            self?.attempted.append(id)
            return UnavailableDevice()
        }, discoverDevices: { [weak self] in self?.scans += 1 }, selectionDelay: 0.02)
    }

    private func settle() {
        let done = expectation(description: "Selection timer and connection callbacks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    func testOpeningAppDoesNotScanOrConnect() throws {
        try makeModel()
        settle()
        XCTAssertEqual(scans, 0)
        XCTAssertTrue(attempted.isEmpty)
    }

    func testRememberedDeviceReconnectsWithoutScanOrFallback() throws {
        let previous = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        try makeModel(remembering: previous)
        model.requestConnection()
        settle()
        XCTAssertEqual(attempted, [previous.id])
        XCTAssertEqual(scans, 0)
        XCTAssertFalse(model.showDevicePicker)
        XCTAssertEqual(model.session.phase, .disconnected)
        XCTAssertNotNil(model.session.message)
        XCTAssertEqual(model.rememberedDevice?.id, previous.id)
    }

    func testSingleDiscoveryConnectsOnlyAfterSelectionWindow() throws {
        try makeModel()
        let device = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        model.requestConnection()
        model.recordDiscoveredDevice(device)
        XCTAssertTrue(attempted.isEmpty)
        XCTAssertTrue(model.scanning)
        settle()
        XCTAssertEqual(attempted, [device.id])
        XCTAssertFalse(model.showDevicePicker)
        XCTAssertFalse(model.scanning)
        XCTAssertNil(model.rememberedDevice, "A failed connection must not be remembered.")
    }

    func testMultipleSameNameDevicesRequireSelection() throws {
        try makeModel()
        let first = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        let second = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        model.requestConnection()
        model.recordDiscoveredDevice(first)
        model.recordDiscoveredDevice(second)
        settle()
        XCTAssertTrue(attempted.isEmpty)
        XCTAssertEqual(model.devices.count, 2)
        XCTAssertTrue(model.showDevicePicker)
        model.connect(second)
        settle()
        XCTAssertEqual(attempted, [second.id])
    }

    func testChangeDeviceDoesNotAutoSelectEvenOneResult() throws {
        let previous = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        try makeModel(remembering: previous)
        model.changeDevice()
        model.recordDiscoveredDevice(IOSDevice(id: UUID(), name: "ES100", signal: nil))
        settle()
        XCTAssertTrue(model.showDevicePicker)
        XCTAssertTrue(attempted.isEmpty)
        XCTAssertEqual(model.rememberedDevice?.id, previous.id)
    }

    func testCancellingScanPreventsDelayedConnectionAndLateDiscoveries() throws {
        try makeModel()
        model.requestConnection()
        model.recordDiscoveredDevice(IOSDevice(id: UUID(), name: "EarStudio", signal: nil))
        model.cancelConnection()
        model.recordDiscoveredDevice(IOSDevice(id: UUID(), name: "ES100", signal: nil))
        settle()
        XCTAssertTrue(attempted.isEmpty)
        XCTAssertFalse(model.scanning)
        XCTAssertFalse(model.showDevicePicker)
        XCTAssertEqual(model.devices.count, 1)
    }

    func testLateSingleResultGetsFullSelectionWindow() throws {
        try makeModel()
        let device = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        model.requestConnection()
        model.recordDiscoveredDevice(device)
        model.finishDiscovery(bluetoothReady: true)
        XCTAssertTrue(attempted.isEmpty)
        XCTAssertFalse(model.showDevicePicker)
        settle()
        XCTAssertEqual(attempted, [device.id])
    }

    func testEmptyScanOffersPickerAndRetry() throws {
        try makeModel()
        model.requestConnection()
        model.finishDiscovery(bluetoothReady: true)
        XCTAssertTrue(model.showDevicePicker)
        XCTAssertFalse(model.scanning)
        XCTAssertTrue(model.connectionMessage?.contains("No EarStudio found") == true)
        XCTAssertTrue(attempted.isEmpty)
    }

    func testCancelledScanIgnoresDeadline() throws {
        try makeModel()
        model.requestConnection()
        model.cancelConnection()
        model.finishDiscovery(bluetoothReady: true)
        XCTAssertFalse(model.showDevicePicker)
    }

    func testRepeatedAdvertisementDoesNotCreateMultipleChoices() throws {
        try makeModel()
        let device = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        model.requestConnection()
        model.recordDiscoveredDevice(device)
        model.recordDiscoveredDevice(device)
        settle()
        XCTAssertEqual(attempted, [device.id])
    }
}

private final class UnavailableDevice: SessionTransport {
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((TransportFailure) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    func open() { onError?(TransportFailure(message: "Device unavailable.")) }
    func send(_ data: Data) -> Bool { false }
    func close(completion: @escaping () -> Void) { completion() }
}
