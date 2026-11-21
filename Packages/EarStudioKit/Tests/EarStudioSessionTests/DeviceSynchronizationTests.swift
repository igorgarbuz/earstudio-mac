import XCTest
import EarStudioCore
import EarStudioSession
import EarStudioUI
import EarStudioTestSupport

/// Exercise the real SwiftUI bindings and readback reconciliation, without Bluetooth
/// or device-token file writes. The fake device independently follows Android's 1...10 IDs.
final class DeviceSynchronizationTests: XCTestCase {
    private func connectedModel(_ link: EQDeviceTransport) -> DeviceSession {
        let model = makeSession()
        model.connect(DeviceConnection(id: "test", name: "ES100", makeTransport: { link }))
        let opened = expectation(description: "Connection callbacks installed")
        DispatchQueue.main.async { opened.fulfill() }
        wait(for: [opened], timeout: 1)

        // Feed synthetic firmware/authentication replies without opening a real channel.
        link.onData?(GAIAPacket(command: 0x8000, payload: [0, 0, 0, 0, 0, 0, 2, 0, 2, 0, 0]).encoded())
        let synced = expectation(description: "Initial EQ readback")
        link.onEQReply = { synced.fulfill() }
        link.onData?(GAIAPacket(command: 0x8303, payload: [0, 0x12, 0x34]).encoded())
        wait(for: [synced], timeout: 2)
        link.onEQReply = nil
        XCTAssertEqual(model.phase, .connected)
        XCTAssertEqual(model.state.bands, link.bands)
        XCTAssertNil(model.message)
        return model
    }

    func testEverySliderChangesOnlyItsOwnDeviceBandWithoutWriteACK() {
        let link = EQDeviceTransport()
        let model = connectedModel(link)
        defer { model.disconnect() }
        var expected = link.bands
        for index in 0..<10 {
            let confirmed = expectation(description: "Confirmed \(DeviceState.bandLabels[index]) Hz")
            link.onEQReply = { confirmed.fulfill() }
            let gain = Double(index - 5) / 10
            model.bandBinding(index).wrappedValue = gain
            expected[index] = gain
            XCTAssertEqual(model.state.bands, expected) // optimistic UI
            wait(for: [confirmed], timeout: 2)
            link.onEQReply = nil
            XCTAssertEqual(link.bandWrites.last, [UInt8(index + 1), UInt8(bitPattern: Int8(index - 5))])
            XCTAssertEqual(link.bands, expected) // all nine neighbors unchanged
            XCTAssertEqual(model.state.bands, expected) // actual readback, not an ACK
            XCTAssertEqual(model.state.preamp, -3)
            XCTAssertEqual(model.pendingCount, 0)
            XCTAssertNil(model.message)
        }
    }

    func testRapidAdjacentSliderEditsCoalesceIndependently() {
        let link = EQDeviceTransport()
        let model = connectedModel(link)
        defer { model.disconnect() }
        var expected = link.bands
        expected[7] = 2.3; expected[8] = -1.6
        let confirmed = expectation(description: "Two distinct bands confirmed")
        confirmed.expectedFulfillmentCount = 2
        link.onEQReply = { confirmed.fulfill() }
        model.bandBinding(7).wrappedValue = 2.1
        model.bandBinding(7).wrappedValue = 2.2
        model.bandBinding(8).wrappedValue = -1.6
        model.bandBinding(7).wrappedValue = 2.3
        wait(for: [confirmed], timeout: 2)
        link.onEQReply = nil
        XCTAssertEqual(link.bandWrites, [[8, 23], [9, UInt8(bitPattern: -16)]])
        XCTAssertEqual(link.bands, expected)
        XCTAssertEqual(model.state.bands, expected)
        XCTAssertEqual(model.pendingCount, 0)
        XCTAssertNil(model.message)
    }

    func testReadbackOfEarlierDragDoesNotOverwriteLaterEdits() {
        let link = EQDeviceTransport()
        let model = connectedModel(link)
        defer { model.disconnect() }
        var expected = link.bands
        expected[7] = 4.4; expected[8] = -3.2
        let confirmed = expectation(description: "Three serialized readbacks")
        confirmed.expectedFulfillmentCount = 3
        link.onEQReply = {
            // The first device readback contains 2.3 at 4k, but 4.4 is pending.
            XCTAssertEqual(model.state.bands, expected)
            XCTAssertNil(model.message)
            confirmed.fulfill()
        }
        link.onBandWrite = {
            link.onBandWrite = nil
            model.bandBinding(8).wrappedValue = -3.2
            model.bandBinding(7).wrappedValue = 4.4
        }
        model.bandBinding(7).wrappedValue = 2.3
        wait(for: [confirmed], timeout: 2)
        link.onEQReply = nil
        XCTAssertEqual(link.bandWrites, [[8, 23], [9, UInt8(bitPattern: -32)], [8, 44]])
        XCTAssertEqual(link.bands, expected)
        XCTAssertEqual(model.state.bands, expected)
        XCTAssertEqual(model.pendingCount, 0)
    }

    func testVolumeWithoutWriteACKIsConfirmedFromActualState() {
        let link = EQDeviceTransport()
        let model = connectedModel(link)
        defer { model.disconnect() }
        let confirmed = expectation(description: "Volume read back")
        link.onStateReply = { confirmed.fulfill() }
        model.doubleBinding(\.volume, .volume, range: -60...6).wrappedValue = -21
        XCTAssertEqual(model.state.volume, -21)
        wait(for: [confirmed], timeout: 2)
        link.onStateReply = nil
        XCTAssertEqual(link.volumeWrites, [[0xEB, 0]])
        XCTAssertEqual(link.volume, -21)
        XCTAssertEqual(model.state.volume, -21)
        XCTAssertEqual(model.state.callVolume, -18)
        XCTAssertEqual(model.state.usbVolume, -6)
        XCTAssertEqual(model.pendingCount, 0)
        XCTAssertNil(model.message)
    }

    func testVolumeAndEQReadbacksPreserveNewerQueuedEdits() {
        let link = EQDeviceTransport()
        let model = connectedModel(link)
        defer { model.disconnect() }
        let confirmed = expectation(description: "Volume, EQ, latest volume confirmed")
        confirmed.expectedFulfillmentCount = 3
        var expectedBands = link.bands; expectedBands[7] = 1.3
        let check = {
            XCTAssertEqual(model.state.volume, -22)
            XCTAssertEqual(model.state.bands, expectedBands)
            XCTAssertNil(model.message)
            confirmed.fulfill()
        }
        link.onStateReply = check; link.onEQReply = check
        link.onVolumeWrite = {
            link.onVolumeWrite = nil
            // The unsolicited notification must not finish the pending transaction.
            link.onData?(GAIAPacket(command: 0x8230, payload: [0] + Wire.volume(-21) + Wire.volume(-18) + Wire.volume(-6)).encoded())
            XCTAssertEqual(model.pendingCount, 1)
            model.bandBinding(7).wrappedValue = 1.3
            model.doubleBinding(\.volume, .volume, range: -60...6).wrappedValue = -21.5
            model.doubleBinding(\.volume, .volume, range: -60...6).wrappedValue = -22
        }
        model.doubleBinding(\.volume, .volume, range: -60...6).wrappedValue = -21
        wait(for: [confirmed], timeout: 2)
        link.onStateReply = nil; link.onEQReply = nil
        XCTAssertEqual(link.volumeWrites, [[0xEB, 0], [0xEA, 0]])
        XCTAssertEqual(link.bandWrites, [[8, 13]])
        XCTAssertEqual(link.volume, -22)
        XCTAssertEqual(model.pendingCount, 0)
    }

    func testIgnoredVolumeWriteShowsActualDeviceValue() {
        let link = EQDeviceTransport()
        let model = connectedModel(link)
        defer { model.disconnect() }
        link.applyVolumeWrites = false
        let confirmed = expectation(description: "Unchanged volume read back")
        link.onStateReply = { confirmed.fulfill() }
        model.doubleBinding(\.volume, .volume, range: -60...6).wrappedValue = -21
        wait(for: [confirmed], timeout: 2)
        link.onStateReply = nil
        XCTAssertEqual(model.state.volume, -32)
        XCTAssertTrue(model.message?.contains("did not apply the volume change") == true)
        XCTAssertEqual(model.pendingCount, 0)
        XCTAssertEqual(link.volumeWrites.count, 1) // No automatic write retry.
    }

    func testFailedVolumeQueryDoesNotDisableEQ() {
        let link = EQDeviceTransport()
        let model = connectedModel(link)
        defer { model.disconnect() }
        link.stateReplyStatus = 1
        let replied = expectation(description: "Rejected state query")
        link.onStateReply = { replied.fulfill() }
        model.doubleBinding(\.volume, .volume, range: -60...6).wrappedValue = -21
        wait(for: [replied], timeout: 2)
        link.onStateReply = nil
        XCTAssertTrue(model.message?.contains("rejected state") == true)
        XCTAssertTrue(model.available(.eq, .eq))
        XCTAssertTrue(model.available(.eq, .band))
        XCTAssertEqual(model.pendingCount, 0)
    }

    func testTruncatedVolumeReadbackDoesNotConfirmOptimisticValue() {
        let link = EQDeviceTransport()
        let model = connectedModel(link)
        defer { model.disconnect() }
        link.truncateStateReply = true
        let replied = expectation(description: "Truncated state query")
        link.onStateReply = { replied.fulfill() }
        model.doubleBinding(\.volume, .volume, range: -60...6).wrappedValue = -21
        wait(for: [replied], timeout: 2)
        link.onStateReply = nil
        XCTAssertEqual(link.volume, -21) // Device applied it; the readback is incomplete.
        XCTAssertEqual(model.state.volume, -32)
        XCTAssertTrue(model.message?.contains("incomplete state reply") == true)
        XCTAssertEqual(model.pendingCount, 0)
    }
}

private final class EQDeviceTransport: SessionTransport {
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((TransportFailure) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onEQReply: (() -> Void)?
    var onStateReply: (() -> Void)?
    var onBandWrite: (() -> Void)?
    var onVolumeWrite: (() -> Void)?
    var bandWrites: [[UInt8]] = []
    var volumeWrites: [[UInt8]] = []
    var volume = -32.0
    var applyVolumeWrites = true
    var stateReplyStatus: UInt8 = 0
    var truncateStateReply = false
    var bands: [Double] = [-6, -4, -2, 0, 1, 3, 5, 2, 4, 6]

    func open() {}
    func close(completion: @escaping () -> Void) { completion() }
    func send(_ data: Data) -> Bool {
        var decoder = GAIAStreamDecoder()
        guard let packet = decoder.append(data).first else { return false }
        var payload: [UInt8]
        switch packet.id {
        case 0x0110:
            guard packet.payload.count == 2 else { return false }
            volumeWrites.append(packet.payload)
            if applyVolumeWrites {
                let raw = UInt16(packet.payload[0]) << 8 | UInt16(packet.payload[1])
                volume = Double(Int16(bitPattern: raw)) / 256
            }
            onVolumeWrite?()
            return true // User reports applied volume changes without a write ACK.
        case 0x0143:
            guard packet.payload.count == 2, (1...10).contains(packet.payload[0]) else { return false }
            bandWrites.append(packet.payload)
            bands[Int(packet.payload[0]) - 1] = Double(Int8(bitPattern: packet.payload[1])) / 10
            onBandWrite?()
            return true // Firmware 2.0.2 sends no write ACK.
        case 0x0000: payload = [0, 0, 0, 0, 0, 0, 2, 0, 2, 0, 0, 1, 15, 0, 0, 0]
        case 0x0001: payload = [0, 7, 0, 0] + Wire.volume(0) + Wire.volume(0) + Wire.volume(6) + [0]
        case 0x0010:
            payload = [stateReplyStatus, 82, 0, 0, 0x80, 0, 1] + Wire.volume(volume) + Wire.volume(-18) + Wire.volume(-6) + [0, 0, 50]
            if truncateStateReply { payload = Array(payload.prefix(8)) }
        case 0x0070: payload = [0, 82, 15, 180]
        case 0x0050: payload = [0, 1, UInt8(bitPattern: -30)] + bands.map { UInt8(bitPattern: Int8(($0 * 10).rounded())) } + [0x11, 0x16, 0x9F]
        default: return false
        }
        let reply = GAIAPacket(command: packet.id | 0x8000, payload: payload)
        DispatchQueue.main.async { [weak self] in
            self?.onData?(reply.encoded())
            if packet.id == 0x0050 { self?.onEQReply?() }
            if packet.id == 0x0010 { self?.onStateReply?() }
        }
        return true
    }
}
