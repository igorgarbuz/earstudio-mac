import XCTest
import EarStudioSession
import EarStudioCore
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

    private func makeModel(remembering device: IOSDevice? = nil, transport: SessionTransport? = nil) throws {
        if let device {
            defaults.set(try JSONEncoder().encode(device), forKey: "lastConnectedEarStudio")
        }
        model = IOSStudioModel(defaults: defaults, makeTransport: { [weak self] id in
            self?.attempted.append(id)
            return transport ?? UnavailableDevice()
        }, discoverDevices: { [weak self] in self?.scans += 1 }, selectionDelay: 0.02)
    }

    private func settle() {
        let done = expectation(description: "Selection timer and connection callbacks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    func testOpeningAppDoesNotScanOrConnect() throws {
        try makeModel()
        model.becameActive()
        settle()
        XCTAssertEqual(scans, 0)
        XCTAssertTrue(attempted.isEmpty)
    }

    func testForegroundReconnectsOnceAndRetriesAfterBackground() throws {
        let previous = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        try makeModel(remembering: previous)
        model.becameActive()
        settle()
        model.becameActive()
        settle()
        XCTAssertEqual(attempted, [previous.id])
        model.enteredBackground()
        model.becameActive()
        settle()
        XCTAssertEqual(attempted, [previous.id, previous.id])
        XCTAssertEqual(scans, 0)
    }

    func testExplicitDisconnectAndCancelSuppressForegroundReconnect() throws {
        let previous = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        try makeModel(remembering: previous)
        model.disconnect()
        model.enteredBackground()
        model.becameActive()
        settle()
        XCTAssertTrue(attempted.isEmpty)
        model.requestConnection()
        settle()
        XCTAssertEqual(attempted, [previous.id])
        model.cancelConnection()
        model.enteredBackground()
        model.becameActive()
        settle()
        XCTAssertEqual(attempted, [previous.id])
    }

    func testPickerCancellationSuppressesReconnectUntilExplicitSelection() throws {
        let previous = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        try makeModel(remembering: previous)
        model.becameActive()
        settle()
        XCTAssertEqual(attempted, [previous.id])
        XCTAssertEqual(model.session.phase, .disconnected)

        model.changeDevice()
        XCTAssertTrue(model.showDevicePicker)
        // The picker Cancel action cancels before dismissing the sheet.
        model.cancelConnection()
        model.showDevicePicker = false
        model.stopDiscovery()
        model.enteredBackground()
        model.becameActive()
        settle()
        XCTAssertEqual(attempted, [previous.id])
        XCTAssertFalse(model.scanning)

        // Selecting a device dismisses the same sheet without cancelling.
        model.changeDevice()
        model.connect(previous)
        model.stopDiscovery()
        settle()
        XCTAssertFalse(model.showDevicePicker)
        XCTAssertEqual(attempted, [previous.id, previous.id])
        model.enteredBackground()
        model.becameActive()
        settle()
        XCTAssertEqual(attempted, [previous.id, previous.id, previous.id])
    }

    func testBackgroundKeepsEstablishedConnectionAndForegroundRefreshesIt() throws {
        let device = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        let link = ConnectedDevice()
        try makeModel(remembering: device, transport: link)
        model.becameActive()
        settle()
        XCTAssertEqual(model.session.phase, .connected)
        link.commands.removeAll()
        model.enteredBackground()
        settle()
        XCTAssertEqual(model.session.phase, .connected)
        XCTAssertEqual(link.closes, 0)
        XCTAssertTrue(link.commands.isEmpty)
        model.becameActive()
        settle()
        XCTAssertEqual(attempted, [device.id])
        XCTAssertEqual(link.closes, 0)
        XCTAssertEqual(link.commands, [0, 1, 16, 112, 80])
        XCTAssertEqual(model.session.refreshStatus, .updated)
    }

    func testConnectionLostInBackgroundReconnectsOnReturn() throws {
        let device = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        let link = ConnectedDevice()
        try makeModel(remembering: device, transport: link)
        model.becameActive()
        settle()
        model.enteredBackground()
        link.onClose?()
        settle()
        XCTAssertEqual(attempted, [device.id])
        model.becameActive()
        settle()
        XCTAssertEqual(attempted, [device.id, device.id])
        XCTAssertEqual(model.session.phase, .connected)
    }

    func testDelayedDisconnectAfterForegroundReconnectsOnlyOnce() throws {
        let device = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        let link = ConnectedDevice()
        try makeModel(remembering: device, transport: link)
        model.becameActive()
        settle()
        model.enteredBackground()
        model.becameActive()
        settle()
        link.onClose?()
        settle()
        XCTAssertEqual(attempted, [device.id, device.id])
        link.onClose?()
        settle()
        XCTAssertEqual(attempted.count, 2, "Do not create an unbounded reconnect loop.")
    }

    func testDemoDoesNotAutoConnect() throws {
        let previous = IOSDevice(id: UUID(), name: "EarStudio", signal: nil)
        try makeModel(remembering: previous)
        model.session.enterDemo()
        model.becameActive()
        model.enteredBackground()
        XCTAssertTrue(model.session.isDemo)
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

private final class ConnectedDevice: SessionTransport {
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((TransportFailure) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var commands: [UInt16] = []
    var closes = 0
    func open() { onOpen?() }
    func close(completion: @escaping () -> Void) { closes += 1; completion() }
    func send(_ data: Data) -> Bool {
        var decoder = GAIAStreamDecoder()
        guard let packet = decoder.append(data).first else { return false }
        commands.append(packet.id)
        let replies: [UInt16: [UInt8]] = [
            0: [0, 0, 0, 0, 1, 0, 2, 0, 2, 0xE7, 0x80, 1, 0x0B, 0x83, 0xE2, 0xC0],
            1: [0, 7, 1, 0xE4, 0xFE, 0x80, 0xFD, 0, 3, 0, 4],
            16: [0, 82, 0xC5, 0x82, 0xB4, 0xF9, 0xC1, 0xDF, 0x80, 0xEE, 0, 0xFA, 0, 0x8B, 0xED, 75],
            80: [0, 1, 0xE2, 0xC4, 0xD8, 0xEC, 0, 10, 30, 50, 20, 40, 60, 0x12, 0x0B, 0x50],
            112: [0, 82, 15, 180]
        ]
        let reply = packet.id == 0x0300
            ? GAIAPacket(command: 0x8303, payload: [0, 0x12, 0x34])
            : GAIAPacket(command: packet.id | 0x8000, payload: replies[packet.id] ?? [0])
        DispatchQueue.main.async { [weak self] in self?.onData?(reply.encoded()) }
        return true
    }
}
