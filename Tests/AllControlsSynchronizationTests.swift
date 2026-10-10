#if !SWIFT_PACKAGE
import XCTest
import IOBluetooth
@testable import EarStudioCompanion

final class AllControlsSynchronizationTests: XCTestCase {
    private func connectedModel(_ link: AllControlsDevice) -> StudioModel {
        let model = StudioModel(makeTransport: { link }, saveDeviceKey: { _, _ in true })
        model.connect(DiscoveredDevice(device: BluetoothTestObjects.device))
        let ready = expectation(description: "Callbacks installed")
        DispatchQueue.main.async { ready.fulfill() }
        wait(for: [ready], timeout: 1)
        let synced = expectation(description: "Initial readback")
        link.onQuery = { if $0 == 0x0050 { synced.fulfill() } }
        // No unsolicited firmware packet: initialization must explicitly read it.
        link.onData?(GAIAPacket(command: 0x8303, payload: [0, 0x12, 0x34]).encoded())
        wait(for: [synced], timeout: 2)
        link.onQuery = nil
        XCTAssertEqual(model.phase, .connected)
        XCTAssertEqual(link.queries, [0, 1, 16, 112, 80])
        link.queries.removeAll()
        return model
    }

    func testEveryControlWithoutWriteACKConfirmsItsOwnFieldAndPreservesNeighbors() {
        // Use the same native bindings/actions as the SwiftUI controls. Literal
        // payloads and the fake's independent bit edits catch UI/wire mismatches.
        typealias Row = (DeviceCommand, [UInt8], (StudioModel) -> Void, (inout DeviceState) -> Void)
        let rows: [Row] = [
            (.dct, [4], { $0.intBinding(\.dct, .dct, range: 0...10).wrappedValue = 4 }, { $0.dct = 4 }),
            (.volume, [0xEB, 0], { $0.doubleBinding(\.volume, .volume, range: -60...6).wrappedValue = -21 }, { $0.volume = -21 }),
            (.mute, [0], { $0.boolBinding(\.muted, .mute).wrappedValue = false }, { $0.muted = false }),
            (.toneVolume, [0xE1, 0x80], { $0.doubleBinding(\.toneVolume, .toneVolume, range: -60...0).wrappedValue = -30.5 }, { $0.toneVolume = -30.5 }),
            (.callMute, [0], { $0.boolBinding(\.callMuted, .callMute).wrappedValue = false }, { $0.callMuted = false }),
            (.trim, [0xFF, 0x80, 0xFE, 0xC0], { $0.setTrim(left: -0.5, right: -1.25) }, { $0.leftTrim = -0.5; $0.rightTrim = -1.25 }),
            (.volumeLimit, [2, 0], { $0.doubleBinding(\.volumeLimit, .volumeLimit, range: -60...6).wrappedValue = 2 }, { $0.volumeLimit = 2 }),
            (.crossfeed, [6], { $0.intBinding(\.crossfeed, .crossfeed, range: 0...10).wrappedValue = 6 }, { $0.crossfeed = 6 }),
            (.oversampling, [1], { $0.intBinding(\.oversampling, .oversampling, range: 0...2).wrappedValue = 1 }, { $0.oversampling = 1 }),
            (.dacFilter, [3], { $0.intBinding(\.dacFilter, .dacFilter, range: 0...3).wrappedValue = 3 }, { $0.dacFilter = 3 }),
            (.jitter, [2], { $0.setJitter(usb: false, bluetooth: true) }, { $0.jitterUSB = false; $0.jitterBluetooth = true }),
            (.eqEnabled, [0], { $0.boolBinding(\.eqEnabled, .eqEnabled).wrappedValue = false }, { $0.eqEnabled = false }),
            (.preamp, [0xE7], { $0.doubleBinding(\.preamp, .preamp, range: -12...12, gain: true).wrappedValue = -2.5 }, { $0.preamp = -2.5 }),
            (.band, [8, 21], { $0.bandBinding(7).wrappedValue = 2.1 }, { $0.bands[7] = 2.1 }),
            (.headroom, [1], { $0.setHeadroom(1, compensation: false) }, { $0.headroom = 1; $0.analogCompensation = false }),
            (.q, [0x16, 0x9F], { $0.setQ(5791) }, { $0.q = 5791 }),
            (.charger, [0], { $0.boolBinding(\.chargerEnabled, .charger).wrappedValue = false }, { $0.chargerEnabled = false }),
            (.autoPower, [2], { $0.intBinding(\.autoPower, .autoPower, range: 0...2).wrappedValue = 2 }, { $0.autoPower = 2 }),
            (.batteryCare, [0], { $0.boolBinding(\.batteryCare, .batteryCare).wrappedValue = false }, { $0.batteryCare = false }),
            (.reconnect, [0], { $0.boolBinding(\.reconnect, .reconnect).wrappedValue = false }, { $0.reconnect = false }),
            (.outputMode, [0x20], { $0.setOutput(3) }, { $0.outputMode = 3 }),
            (.outputLock, [1], { $0.boolBinding(\.outputLocked, .outputLock).wrappedValue = true }, { $0.outputLocked = true }),
            (.codecs, [5], { $0.setCodecs(aac: false, aptx: true, hd: false) }, { $0.aac = false; $0.aptx = true; $0.aptxHD = false }),
            (.buffer, [8], { $0.intBinding(\.buffer, .buffer, range: 1...10).wrappedValue = 8 }, { $0.buffer = 8 }),
            (.mic, [22], { $0.setMic(ambient: false, preamp: false, gain: 22) }, { $0.micPreamp = false; $0.micGain = 22 }),
            (.loopback, [0xD4, 0x80], { $0.doubleBinding(\.loopback, .loopback, range: -60...0).wrappedValue = -43.5 }, { $0.loopback = -43.5 }),
            (.hfp, [0], { $0.intBinding(\.hfp, .hfp, range: 0...1).wrappedValue = 0 }, { $0.hfp = 0 }),
            (.ambient, [0], { $0.boolBinding(\.ambient, .ambient).wrappedValue = false }, { $0.ambient = false }),
            (.ambientMic, [7], { $0.setMic(ambient: true, preamp: false, gain: 7) }, { $0.ambientPreamp = false; $0.ambientGain = 7 }),
            (.ambientRatio, [40], { $0.intBinding(\.ambientRatio, .ambientRatio, range: 0...100).wrappedValue = 40 }, { $0.ambientRatio = 40 }),
            (.ambientShortcut, [0], { $0.boolBinding(\.ambientShortcut, .ambientShortcut).wrappedValue = false }, { $0.ambientShortcut = false }),
            (.led, [2], { $0.intBinding(\.led, .led, range: 0...2).wrappedValue = 2 }, { $0.led = 2 }),
            (.usbBits, [1], { $0.intBinding(\.usbBits, .usbBits, range: 0...2).wrappedValue = 1 }, { $0.usbBits = 1 })
        ]
        for (command, payload, edit, mutateExpected) in rows {
            let link = AllControlsDevice()
            let model = connectedModel(link)
            var expected = model.state; mutateExpected(&expected)
            let done = expectation(description: "Confirm \(command)")
            link.onQuery = { _ in done.fulfill() }
            edit(model)
            wait(for: [done], timeout: 2)
            link.onQuery = nil
            XCTAssertEqual(link.writes.map(\.id), [command.rawValue], "\(command)")
            XCTAssertEqual(link.writes.first?.payload, payload, "\(command)")
            XCTAssertEqual(link.queries, [command.confirmationReadback!.rawValue], "\(command)")
            XCTAssertEqual(model.state, expected, "\(command): only intended fields change")
            XCTAssertNil(model.message, "\(command)")
            XCTAssertEqual(model.pendingCount, 0)
            model.disconnect()
        }
    }

    func testCoupledSettingsCoalesceAndPreserveTheNewestOtherHalf() {
        let link = AllControlsDevice(); link.sendWriteACK = true
        let model = connectedModel(link)
        defer { model.disconnect() }
        let done = expectation(description: "Two packed settings confirmed"); done.expectedFulfillmentCount = 2
        link.onQuery = { _ in done.fulfill() }
        model.setMic(ambient: true, preamp: false, gain: 13)
        model.setMic(ambient: true, preamp: model.state.ambientPreamp, gain: 8)
        model.setCodecs(aac: false, aptx: model.state.aptx, hd: model.state.aptxHD)
        model.setCodecs(aac: model.state.aac, aptx: true, hd: model.state.aptxHD)
        model.setCodecs(aac: model.state.aac, aptx: model.state.aptx, hd: false)
        wait(for: [done], timeout: 2)
        link.onQuery = nil
        XCTAssertEqual(link.writes.map(\.payload), [[8], [5]])
        XCTAssertEqual(model.state.ambientGain, 8); XCTAssertFalse(model.state.ambientPreamp)
        XCTAssertFalse(model.state.aac); XCTAssertTrue(model.state.aptx); XCTAssertFalse(model.state.aptxHD)
        XCTAssertNil(model.message)
    }

    func testIgnoredPackedWriteRollsBackActualFields() {
        let link = AllControlsDevice(); let model = connectedModel(link)
        defer { model.disconnect() }
        let original = model.state
        link.applyWrites = false; link.sendWriteACK = true
        let done = expectation(description: "Read actual codec settings")
        link.onQuery = { _ in done.fulfill() }
        model.setCodecs(aac: false, aptx: true, hd: false)
        wait(for: [done], timeout: 2)
        link.onQuery = nil
        XCTAssertEqual(model.state, original)
        XCTAssertTrue(model.message?.contains("did not apply the codecs change") == true)
        XCTAssertEqual(link.writes.count, 1) // an ACK cannot confirm a rejected value
    }

    func testRejectedQueryDisablesOnlyControlsDependingOnThatQuery() {
        let link = AllControlsDevice(); let model = connectedModel(link)
        defer { model.disconnect() }
        link.queryStatus = 1
        let done = expectation(description: "Readback rejected")
        link.onQuery = { _ in done.fulfill() }
        model.setCodecs(aac: false, aptx: true, hd: false)
        wait(for: [done], timeout: 2)
        link.onQuery = nil
        XCTAssertFalse(model.available(.device, .codecs))
        XCTAssertFalse(model.available(.device, .crossfeed))
        XCTAssertTrue(model.available(.audio, .mic))
        XCTAssertTrue(model.available(.eq, .band))
        XCTAssertTrue(model.available(.info, .led))
    }

    func testTrimRejectsNonfiniteInputAndOutputLockBlocksModeWrites() {
        let model = StudioModel(demo: true)
        let original = model.state
        model.setTrim(left: .nan, right: -3)
        XCTAssertEqual(model.state, original)
        model.boolBinding(\.outputLocked, .outputLock).wrappedValue = true
        model.setOutput(3)
        XCTAssertEqual(model.state.outputMode, original.outputMode)
    }

    func testFactoryPresetsPreserveProcessingSettingsAndSavedLibrary() {
        // Rock, Flat and Bass Reducer cover mixed, zero and negative gains.
        for index in [16, 7, 2] {
            let link = AllControlsDevice()
            link.replies[80]![1] = 0 // Keep EQ bypassed.
            link.replies[80]![2] = 20 // Existing +2 dB preamp must reset to zero.
            link.replies[80]![13] = 2 // -12 dB headroom, compensation off.
            link.replies[80]![14] = 0x0B; link.replies[80]![15] = 0x50 // Wide Q.
            let model = connectedModel(link)
            let saved = model.presets
            let preset = FactoryEQPreset.all[index]
            var expected = model.state
            expected.preamp = 0; expected.bands = preset.bands
            let done = expectation(description: "Factory preset \(preset.name) read back")
            link.onQuery = { _ in done.fulfill() }
            model.applyFactoryPreset(preset)
            wait(for: [done], timeout: 2)
            link.onQuery = nil
            XCTAssertEqual(link.writes.map(\.id), [0x0144])
            XCTAssertEqual(link.queries, [0x0050])
            XCTAssertEqual(model.state, expected, "Factory presets change only preamp and bands")
            XCTAssertEqual(model.presets, saved)
            XCTAssertEqual(model.presetName, preset.name)
            XCTAssertEqual(model.pendingCount, 0)
            XCTAssertNil(model.message)
            model.disconnect()
        }
    }

    func testPresetGainsQAndHeadroomAreSerializedAndReadBack() {
        let link = AllControlsDevice(); let model = connectedModel(link)
        defer { model.disconnect() }
        let done = expectation(description: "Three preset settings confirmed"); done.expectedFulfillmentCount = 3
        link.onQuery = { _ in done.fulfill() }
        model.applyPreset(.flat)
        wait(for: [done], timeout: 3)
        link.onQuery = nil
        XCTAssertEqual(link.writes.map(\.id), [0x0144, 0x0146, 0x0145])
        XCTAssertEqual(link.writes[0].payload, Array(repeating: 0, count: 11))
        XCTAssertEqual(model.state.bands, Array(repeating: 0, count: 10))
        XCTAssertEqual(model.state.preamp, 0); XCTAssertEqual(model.state.q, EQPreset.flat.q)
        XCTAssertEqual(model.state.headroom, EQPreset.flat.headroom)
        XCTAssertNil(model.message)
    }

    func testTruncatedFullDetailsCannotConfirmCodecWritesFromOldFields() {
        let link = AllControlsDevice(); let model = connectedModel(link)
        defer { model.disconnect() }
        let original = model.state
        link.truncateDetails = true
        let done = expectation(description: "Short full settings reply")
        link.onQuery = { _ in done.fulfill() }
        model.setCodecs(aac: false, aptx: true, hd: false)
        wait(for: [done], timeout: 2)
        link.onQuery = nil
        XCTAssertEqual(model.state, original)
        XCTAssertTrue(model.message?.contains("incomplete deviceDetails reply") == true)
        XCTAssertEqual(model.pendingCount, 0)
    }

    func testLegacyFirmwareDoesNotClampVolumeToAnUnavailableLimit() {
        let link = AllControlsDevice()
        link.replies[0]![6...8] = [1, 3, 1]
        link.replies[1] = Array(link.replies[1]!.prefix(8))
        link.replies[80] = Array(link.replies[80]!.prefix(13))
        let model = connectedModel(link)
        defer { model.disconnect() }
        let done = expectation(description: "Positive legacy volume confirmed")
        link.onQuery = { _ in done.fulfill() }
        model.doubleBinding(\.volume, .volume, range: -60...6).wrappedValue = 2
        wait(for: [done], timeout: 2)
        link.onQuery = nil
        XCTAssertEqual(link.writes.first?.payload, [2, 0])
        XCTAssertEqual(model.state.volume, 2)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.available(.info, .volumeLimit))
    }
}

/// Independent firmware fixture: edits literal packed bytes, never DeviceState
/// or DeviceCommand.matchesReadback, and deliberately omits successful write ACKs.
private final class AllControlsDevice: ControlTransport {
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((TransportFailure) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onQuery: ((UInt16) -> Void)?
    var sendWriteACK = false
    var applyWrites = true
    var queryStatus: UInt8 = 0
    var truncateDetails = false
    var writes: [GAIAPacket] = []
    var queries: [UInt16] = []
    var replies: [UInt16: [UInt8]] = [0: ControlFixtures.details, 1: ControlFixtures.info, 16: ControlFixtures.audio, 80: ControlFixtures.eq, 112: [0, 82, 15, 180]]
    init() { replies[16]![6] = 1 } // unlocked, single-ended normal power
    func connect(_ target: IOBluetoothDevice) {}
    func close(completion: @escaping () -> Void) { completion() }
    func send(_ data: Data) -> Bool {
        var decoder = GAIAStreamDecoder()
        guard let packet = decoder.append(data).first else { return false }
        if var reply = replies[packet.id] {
            queries.append(packet.id); reply[0] = queryStatus
            if truncateDetails, packet.id == 0 { reply = Array(reply.prefix(11)) }
            DispatchQueue.main.async { [weak self] in
                self?.onData?(GAIAPacket(command: packet.id | 0x8000, payload: reply).encoded())
                self?.onQuery?(packet.id)
            }
            return true
        }
        writes.append(packet)
        let p = packet.payload
        if applyWrites {
            func replace(_ query: UInt16, _ offset: Int, _ value: [UInt8]) {
                replies[query]!.replaceSubrange(offset..<(offset + value.count), with: value)
            }
            func bits(_ query: UInt16, _ offset: Int, _ mask: UInt8, _ value: UInt8) {
                replies[query]![offset] = (replies[query]![offset] & ~mask) | value
            }
            switch packet.id {
            case 0x0102: bits(16, 2, 15, p[0])
            case 0x0110: replace(16, 7, p)
            case 0x0111: bits(16, 5, 128, p[0] << 7)
            case 0x0112: replace(0, 9, p)
            case 0x0113: bits(16, 5, 64, p[0] << 6)
            case 0x0114: replace(1, 4, p)
            case 0x0115: replace(1, 8, p)
            case 0x0120: bits(0, 13, 15, p[0])
            case 0x0121: bits(16, 2, 96, p[0] << 5)
            case 0x0123: bits(16, 3, 3, p[0])
            case 0x0125: bits(16, 4, 48, p[0] << 4)
            case 0x0141: replace(80, 1, p)
            case 0x0142: replace(80, 2, p)
            case 0x0143: replace(80, Int(p[0]) + 2, [p[1]])
            case 0x0144: replace(80, 2, p)
            case 0x0145: replace(80, 13, p)
            case 0x0146: replace(80, 14, p)
            case 0x0151: bits(16, 5, 1, p[0])
            case 0x0153: bits(0, 13, 192, p[0] == 1 ? 128 : (p[0] == 2 ? 64 : 0))
            case 0x0157: bits(1, 3, 128, p[0] << 7)
            case 0x0158: bits(1, 3, 64, p[0] << 6)
            case 0x0160: bits(16, 6, 97, p[0])
            case 0x0161: bits(16, 6, 128, p[0] << 7)
            case 0x0162: replace(0, 12, p)
            case 0x0163: bits(1, 1, 15, p[0])
            case 0x0170: replace(16, 13, p)
            case 0x0171: replace(0, 14, p)
            case 0x0172: bits(1, 3, 32, p[0] << 5)
            case 0x0180: bits(16, 14, 128, p[0] << 7)
            case 0x0181: bits(16, 14, 95, (p[0] & 31) | ((p[0] & 128) >> 1))
            case 0x0182: replace(16, 15, p)
            case 0x0183: bits(16, 14, 32, p[0] << 5)
            case 0x0190: bits(1, 2, 15, p[0])
            case 0x01A0: bits(1, 10, 6, p[0] << 1)
            default: return false
            }
        }
        if sendWriteACK {
            DispatchQueue.main.async { [weak self] in self?.onData?(GAIAPacket(command: packet.id | 0x8000, payload: [0]).encoded()) }
        }
        return true
    }
}
#endif
