import XCTest
#if SWIFT_PACKAGE
@testable import EarStudioCore
#else
@testable import EarStudioCompanion
#endif

/// Literal fixtures transcribed from Android GaiaCommandManager's decoders.
/// These deliberately do not use our command encoders to construct readbacks.
enum ControlFixtures {
    static let details: [UInt8] = [0, 0, 0, 0, 1, 0, 2, 0, 2, 0xE7, 0x80, 1, 0x0B, 0x83, 0xE2, 0xC0]
    static let info: [UInt8] = [0, 7, 1, 0xE4, 0xFE, 0x80, 0xFD, 0, 3, 0, 4]
    static let audio: [UInt8] = [0, 82, 0xC5, 0x82, 0xB4, 0xF9, 0xC1, 0xDF, 0x80, 0xEE, 0, 0xFA, 0, 0x8B, 0xED, 75]
    static let eq: [UInt8] = [0, 1, 0xE2, 0xC4, 0xD8, 0xEC, 0, 10, 30, 50, 20, 40, 60, 0x12, 0x0B, 0x50]
    static var state: DeviceState {
        var state = DeviceState()
        for (id, payload): (UInt16, [UInt8]) in [(0x8000, details), (0x8001, info), (0x8010, audio), (0x8050, eq)] {
            precondition(state.apply(GAIAPacket(command: id, payload: payload)))
        }
        return state
    }
    // Every setting exposed by the UI, with independent expected wire payloads.
    static let settings: [(DeviceCommand, [UInt8], DeviceCommand)] = [
        (.dct, [5], .state), (.volume, [0xDF, 0x80], .state), (.mute, [1], .state),
        (.toneVolume, [0xE7, 0x80], .deviceDetails), (.callMute, [1], .state),
        (.trim, [0xFE, 0x80, 0xFD, 0], .deviceInfo), (.volumeLimit, [3, 0], .deviceInfo),
        (.crossfeed, [3], .deviceDetails), (.oversampling, [2], .state), (.dacFilter, [2], .state),
        (.jitter, [3], .state),
        (.eqEnabled, [1], .eq), (.preamp, [0xE2], .eq), (.band, [8, 20], .eq),
        (.allGains, [0xE2, 0xC4, 0xD8, 0xEC, 0, 10, 30, 50, 20, 40, 60], .eq),
        (.headroom, [0x12], .eq), (.q, [0x0B, 0x50], .eq),
        (.charger, [1], .state), (.autoPower, [1], .deviceDetails), (.batteryCare, [1], .deviceInfo),
        (.reconnect, [1], .deviceInfo), (.outputMode, [0x41], .state), (.outputLock, [1], .state),
        (.codecs, [0x0B], .deviceDetails), (.buffer, [7], .deviceInfo), (.mic, [0x8B], .state),
        (.loopback, [0xE2, 0xC0], .deviceDetails), (.hfp, [1], .deviceInfo),
        (.ambient, [1], .state), (.ambientMic, [0x8D], .state), (.ambientRatio, [75], .state),
        (.ambientShortcut, [1], .state), (.led, [1], .deviceInfo), (.usbBits, [2], .deviceInfo)
    ]
}

final class ControlMappingTests: XCTestCase {
    func testEveryExposedSettingHasTheCorrectQueryAndMatchingField() {
        let state = ControlFixtures.state
        let settings = Set(ControlFixtures.settings.map { $0.0 })
        let excluded: Set<DeviceCommand> = [.authenticate, .cancelAuthentication, .batteryInterval]
        XCTAssertEqual(settings, Set(DeviceCommand.allCases.filter { !$0.isRead }).subtracting(excluded))
        for (command, payload, query) in ControlFixtures.settings {
            XCTAssertEqual(command.confirmationReadback, query, "\(command)")
            XCTAssertTrue(command.matchesReadback(payload, state: state), "\(command)")
            var different = payload; different[different.count - 1] ^= 1
            XCTAssertFalse(command.matchesReadback(different, state: state), "\(command)")
            XCTAssertFalse(command.matchesReadback([], state: state), "\(command)")
        }
    }

    func testLiteralPackedFieldsDecodeToAndroidValues() {
        let s = ControlFixtures.state
        XCTAssertEqual(s.firmware, "2.0.2")
        XCTAssertEqual(s.toneVolume, -24.5); XCTAssertEqual(s.loopback, -29.25)
        XCTAssertTrue(s.aac); XCTAssertFalse(s.aptx); XCTAssertTrue(s.aptxHD)
        XCTAssertEqual(s.autoPower, 1); XCTAssertEqual(s.crossfeed, 3)
        XCTAssertEqual(s.leftTrim, -1.5); XCTAssertEqual(s.rightTrim, -3)
        XCTAssertEqual(s.volumeLimit, 3); XCTAssertEqual(s.usbBits, 2)
        XCTAssertTrue(s.batteryCare && s.reconnect); XCTAssertEqual(s.hfp, 1)
        XCTAssertEqual(s.codec, 4); XCTAssertEqual(s.buffer, 7); XCTAssertEqual(s.led, 1)
        XCTAssertEqual(s.volume, -32.5); XCTAssertEqual(s.callVolume, -18); XCTAssertEqual(s.usbVolume, -6)
        XCTAssertEqual(s.outputMode, 1); XCTAssertTrue(s.outputLocked)
        XCTAssertTrue(s.jitterUSB && s.jitterBluetooth)
        XCTAssertEqual(s.oversampling, 2); XCTAssertEqual(s.dct, 5); XCTAssertEqual(s.dacFilter, 2)
        XCTAssertTrue(s.micPreamp); XCTAssertEqual(s.micGain, 11)
        XCTAssertTrue(s.ambient && s.ambientPreamp && s.ambientShortcut)
        XCTAssertEqual(s.ambientGain, 13); XCTAssertEqual(s.ambientRatio, 75)
        XCTAssertEqual(s.q, 2896); XCTAssertEqual(s.headroom, 2); XCTAssertTrue(s.analogCompensation)
    }

    func testEverySettingWaitsForReadbackRegardlessOfOptionalWriteACK() {
        for (command, payload, query) in ControlFixtures.settings {
            var queue = CommandQueue()
            queue.enqueue(.init(command: command, payload: payload))
            let item = queue.next()!
            XCTAssertNil(queue.acknowledge(GAIAPacket(command: command.rawValue | 0x8000, payload: [0])))
            XCTAssertNil(queue.acknowledge(GAIAPacket(command: query.rawValue | 0x8000, payload: [0])))
            XCTAssertEqual(queue.beginReadback(for: item.token), query)
            XCTAssertNil(queue.acknowledge(GAIAPacket(command: command.rawValue | 0x8000, payload: [0])))
            XCTAssertEqual(queue.acknowledge(GAIAPacket(command: query.rawValue | 0x8000, payload: [0]))?.token, item.token)
        }
    }

    func testAllFirmwareGatesAtTheirBoundaries() {
        let gated: [(DeviceCommand, String, String)] = [
            (.toneVolume, "1.1.2", "1.1.3"), (.oversampling, "1.1.3", "1.1.4"),
            (.ambientShortcut, "1.1.3", "1.1.4"), (.codecs, "1.1.7", "1.1.8"),
            (.dct, "1.1.9", "1.2.0"), (.crossfeed, "1.1.9", "1.2.0"), (.loopback, "1.1.9", "1.2.0"),
            (.buffer, "1.2.0", "1.2.1"), (.led, "1.2.1", "1.2.2"),
            (.batteryCare, "1.2.3", "1.2.4"), (.autoPower, "1.2.9", "1.3.0"), (.trim, "1.3.0", "1.3.1"),
            (.headroom, "1.3.9", "1.4.0"), (.volumeLimit, "1.3.9", "1.4.0"),
            (.reconnect, "1.3.9", "1.4.0"), (.hfp, "1.3.9", "1.4.0"), (.usbBits, "1.3.9", "1.4.0"),
            (.q, "1.4.2", "1.4.3")
        ]
        for (command, before, minimum) in gated {
            var state = DeviceState()
            XCTAssertFalse(command.supported(by: state), "\(command) without firmware")
            state.firmware = before; XCTAssertFalse(command.supported(by: state), "\(command)")
            state.firmware = minimum; XCTAssertTrue(command.supported(by: state), "\(command)")
            state.firmware = "2.0.2"; XCTAssertTrue(command.supported(by: state), "\(command)")
        }
    }

    func testFirmwareMustLoadBeforeVersionDependentPackets() {
        var state = DeviceState()
        XCTAssertFalse(state.apply(GAIAPacket(command: 0x8001, payload: ControlFixtures.info)))
        XCTAssertFalse(state.apply(GAIAPacket(command: 0x8050, payload: ControlFixtures.eq)))
        XCTAssertTrue(state.loaded.isEmpty)
        XCTAssertTrue(state.apply(GAIAPacket(command: 0x8000, payload: Array(ControlFixtures.details.prefix(11)))))
        XCTAssertEqual(state.firmware, "2.0.2")
        XCTAssertFalse(state.loaded.contains(.device)) // absent fields cannot enable controls
        XCTAssertTrue(state.apply(GAIAPacket(command: 0x8001, payload: ControlFixtures.info)))
        XCTAssertTrue(state.apply(GAIAPacket(command: 0x8050, payload: ControlFixtures.eq)))
    }

    func testVersionedReadbacksAndEveryTruncationAreAtomic() {
        for (firmware, infoLength, eqLength): (String, Int, Int) in [
            ("1.1.3", 3, 13), ("1.2.4", 4, 13), ("1.3.1", 8, 13), ("1.4.0", 10, 14), ("1.4.3", 11, 16), ("2.0.2", 11, 16)
        ] {
            var original = ControlFixtures.state; original.firmware = firmware
            for (id, bytes, length): (UInt16, [UInt8], Int) in [(0x8001, ControlFixtures.info, infoLength), (0x8050, ControlFixtures.eq, eqLength)] {
                for count in 0..<length {
                    var state = original
                    XCTAssertFalse(state.apply(GAIAPacket(command: id, payload: Array(bytes.prefix(count)))))
                    XCTAssertEqual(state, original, "\(firmware), ID \(id), \(count) bytes")
                }
                var state = original
                XCTAssertTrue(state.apply(GAIAPacket(command: id, payload: Array(bytes.prefix(length)))))
            }
        }
    }

    func testLegacyUSBFormatBitDoesNotDecodeHFPAsModernFormat() {
        var state = DeviceState(); state.firmware = "1.4.0"
        var payload = Array(ControlFixtures.info.prefix(10)); payload[3] = 0xB1
        XCTAssertTrue(state.apply(GAIAPacket(command: 0x8001, payload: payload)))
        XCTAssertEqual(state.usbBits, 1); XCTAssertEqual(state.hfp, 1)
        XCTAssertTrue(state.apply(GAIAPacket(command: 0x8001, payload: payload + [4])))
        XCTAssertEqual(state.usbBits, 1) // padding must not select the newer layout
        state.firmware = "1.4.3"; payload += [4]
        XCTAssertTrue(state.apply(GAIAPacket(command: 0x8001, payload: payload)))
        XCTAssertEqual(state.usbBits, 2)
    }
}
