import XCTest
#if SWIFT_PACKAGE
@testable import EarStudioCore
#else
@testable import EarStudioCompanion
#endif

final class ProtocolTests: XCTestCase {
    func testExactAndroidFrameFixtures() {
        XCTAssertEqual(Array(DeviceCommand.authenticate.packet(Wire.u16(0x1234)).encoded()), [0xFF, 1, 0, 2, 0xA5, 0x5A, 3, 0, 0x12, 0x34])
        XCTAssertEqual(Array(DeviceCommand.volume.packet(Wire.volume(-32.5)).encoded()), [0xFF, 1, 0, 2, 0xA5, 0x5A, 1, 0x10, 0xDF, 0x80])
        XCTAssertEqual(Array(DeviceCommand.band.packet([3, Wire.gain(-1.2)]).encoded()), [0xFF, 1, 0, 2, 0xA5, 0x5A, 1, 0x43, 3, 0xF4])
        XCTAssertEqual(DeviceCommand.cancelAuthentication.rawValue, 0x0301)
    }
    func testStreamFragmentationAndCoalescingAtEveryBoundary() {
        let a = GAIAPacket(command: 0x8070, payload: [0, 82, 15, 180])
        let b = GAIAPacket(command: 0x8110, payload: [0], flags: 1)
        let bytes = a.encoded() + b.encoded()
        for split in 0...bytes.count {
            var decoder = GAIAStreamDecoder()
            let decoded = decoder.append(bytes.prefix(split)) + decoder.append(bytes.dropFirst(split))
            XCTAssertEqual(decoded, [a, b], "Split \(split)")
        }
    }
    func testNoiseBadChecksumAndMalformedHeaderRecover() {
        let valid = GAIAPacket(command: 0x8070, payload: [0, 75, 15, 200], flags: 1)
        var corrupted = valid.encoded(); corrupted[corrupted.count - 1] ^= 0x80
        var decoder = GAIAStreamDecoder()
        let data = Data([1, 2, 0xFF, 2, 0, 0, 0xFF, 1, 2, 0]) + corrupted + valid.encoded()
        XCTAssertEqual(decoder.append(data), [valid])
        XCTAssertEqual(decoder.rejectedFrames, 3)
    }
    func testSignedWireUnitsAndJavaRounding() {
        for value in [-60.0, -32.5, -0.5, 0, 6] { XCTAssertEqual(Wire.readVolume(Wire.volume(value), 0), value) }
        XCTAssertEqual(Wire.readGain(Wire.gain(-0.05)), 0)
        XCTAssertEqual(Wire.readGain(Wire.gain(0.05)), 0.1)
        XCTAssertEqual(Wire.readGain(Wire.gain(-12)), -12)
        XCTAssertEqual(Wire.readGain(Wire.gain(.infinity)), 0)
        XCTAssertEqual(Wire.readU16(Wire.u16(5791), 0), 5791)
    }
    func testStateOffsetsAndPackedBits() {
        var state = DeviceState()
        let payload: [UInt8] = [0, 82, 0xA3, 0x82, 0xB4, 0xB9, 0xA0] + Wire.volume(-32.5) + Wire.volume(-18) + Wire.volume(-6) + [0x8B, 0xED, 75]
        XCTAssertTrue(state.apply(GAIAPacket(command: 0x8010, payload: payload)))
        XCTAssertEqual(state.battery, 82)
        XCTAssertEqual(state.volume, -32.5)
        XCTAssertEqual(state.callVolume, -18)
        XCTAssertEqual(state.usbVolume, -6)
        XCTAssertEqual(state.outputMode, 3)
        XCTAssertTrue(state.outputLocked)
        XCTAssertEqual(state.input, 2)
        XCTAssertEqual(state.oversampling, 1)
        XCTAssertEqual(state.dct, 3)
        XCTAssertTrue(state.dctEnabled)
        XCTAssertTrue(state.callActive)
        XCTAssertTrue(state.muted)
        XCTAssertTrue(state.charging)
        XCTAssertTrue(state.ambient && state.ambientPreamp && state.ambientShortcut)
        XCTAssertEqual(state.ambientGain, 13)
        XCTAssertEqual(state.ambientRatio, 75)
    }
    func testEQReadbackPreservesSignedGainsAndQ() {
        var state = DeviceState()
        let bands = [-12.0, -6, -3, -1, 0, 0.1, 1, 3, 6, 12]
        let payload: [UInt8] = [0, 1, Wire.gain(-3)] + bands.map(Wire.gain) + [0x12] + Wire.u16(2896)
        XCTAssertTrue(state.apply(GAIAPacket(command: 0x8050, payload: payload)))
        XCTAssertEqual(state.bands, bands)
        XCTAssertEqual(state.preamp, -3)
        XCTAssertTrue(state.eqEnabled)
        XCTAssertEqual(state.q, 2896)
        XCTAssertEqual(state.headroom, 2)
        XCTAssertTrue(state.analogCompensation)
    }
    func testTruncatedAndFailedRepliesDoNotChangeState() {
        let original = DeviceState.demo
        for count in 0..<16 {
            var state = original
            XCTAssertFalse(state.apply(GAIAPacket(command: 0x8010, payload: Array(repeating: 0, count: count))))
            XCTAssertEqual(state, original)
        }
        var state = original
        XCTAssertFalse(state.apply(GAIAPacket(command: 0x8050, payload: [1] + Array(repeating: 0, count: 15))))
        XCTAssertFalse(state.apply(GAIAPacket(vendor: 1, command: 0x8070, payload: [0, 1, 2, 3])))
        XCTAssertFalse(state.apply(GAIAPacket(command: 0x8050, payload: Array(repeating: 0, count: 14))))
        XCTAssertFalse(state.apply(GAIAPacket(command: 0x8001, payload: Array(repeating: 0, count: 8))))
        XCTAssertEqual(state, original)
    }
    func testQueueCoalescesPendingButPreservesInFlightAndBandIdentity() {
        var queue = CommandQueue()
        queue.enqueue(.init(command: .volume, payload: Wire.volume(-40), key: "volume"))
        let first = queue.next()!
        queue.enqueue(.init(command: .volume, payload: Wire.volume(-30), key: "volume"))
        queue.enqueue(.init(command: .volume, payload: Wire.volume(-20), key: "volume"))
        queue.enqueue(.init(command: .band, payload: [0, 10], key: "band-0"))
        queue.enqueue(.init(command: .band, payload: [1, 20], key: "band-1"))
        XCTAssertEqual(queue.inFlight?.token, first.token)
        XCTAssertEqual(queue.pending.count, 3)
        XCTAssertNil(queue.next())
        XCTAssertNil(queue.acknowledge(0x0230)) // unsolicited notification cannot finish a write
        XCTAssertEqual(queue.acknowledge(0x0110)?.token, first.token)
        XCTAssertEqual(queue.next()?.payload, Wire.volume(-20))
    }
    func testPresetJSONRoundTripAndAndroidXML() throws {
        let encoded = try JSONEncoder().encode(PresetFile(presets: [.flat]))
        XCTAssertEqual(try PresetFile.decode(encoded), [.flat])
        let xml = """
        <?xml version="1.0"?><map>
        <string name="Preset_name_1">Warm &amp; clear</string>
        <string name="radsone_eq_pre1">-3,3,2,1,0,-1,0,1,2,3,0</string>
        </map>
        """
        let presets = try PresetFile.decode(Data(xml.utf8))
        XCTAssertEqual(presets.count, 1)
        XCTAssertEqual(presets[0].name, "Warm & clear")
        XCTAssertEqual(presets[0].preamp, -3)
        XCTAssertEqual(presets[0].bands.count, 10)
        XCTAssertEqual(presets[0].q, 5791)
    }
    func testInvalidPresetsAreRejected() throws {
        var bad = EQPreset.flat; bad.bands[4] = 50
        XCTAssertThrowsError(try PresetFile.decode(JSONEncoder().encode(PresetFile(presets: [bad]))))
        bad = .flat; bad.bands.removeLast()
        XCTAssertThrowsError(try bad.validated())
        var future = PresetFile(presets: [.flat]); future.version = 99
        XCTAssertThrowsError(try PresetFile.decode(JSONEncoder().encode(future)))
        XCTAssertThrowsError(try PresetFile.decode(Data(repeating: 0, count: 1_048_577)))
        XCTAssertThrowsError(try PresetFile.decode(Data("<map/>".utf8)))
    }
    func testFlatResponseAndFirmwareGates() {
        for frequency in DeviceState.frequencies {
            XCTAssertEqual(EQResponse.decibels(at: frequency, gains: EQPreset.flat.bands, preamp: -3, q: 1.4142), -3, accuracy: 0.00001)
        }
        var state = DeviceState()
        XCTAssertFalse(state.supportsQ)
        state.firmware = "1.4.0"; XCTAssertTrue(state.supportsHeadroom); XCTAssertFalse(state.supportsQ)
        state.firmware = "1.4.3"; XCTAssertTrue(state.supportsQ)
    }
    func testMicrophoneGainTableUsesHardwareSteps() {
        var state = DeviceState()
        state.micGain = 0
        XCTAssertEqual(state.microphoneDecibels(ambient: false), -27)
        state.micGain = 11
        XCTAssertEqual(state.microphoneDecibels(ambient: false), 6)
        state.micPreamp = true
        XCTAssertEqual(state.microphoneDecibels(ambient: false), 27)
        state.ambientGain = 22; state.ambientPreamp = true
        XCTAssertEqual(state.microphoneDecibels(ambient: true), 60.5)
    }
}
