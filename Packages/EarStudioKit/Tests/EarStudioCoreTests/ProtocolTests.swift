import XCTest
@testable import EarStudioCore

final class ProtocolTests: XCTestCase {
    func testExactAndroidFrameFixtures() {
        XCTAssertEqual(Array(DeviceCommand.authenticate.packet(Wire.u16(0x1234)).encoded()), [0xFF, 1, 0, 2, 0xA5, 0x5A, 3, 0, 0x12, 0x34])
        XCTAssertEqual(Array(DeviceCommand.volume.packet(Wire.volume(-32.5)).encoded()), [0xFF, 1, 0, 2, 0xA5, 0x5A, 1, 0x10, 0xDF, 0x80])
        // Android seekbar ID 4 is the 250 Hz band (UI array index 3).
        XCTAssertEqual(Array(DeviceCommand.band.packet(Wire.bandGain(at: 3, gain: -1.2)).encoded()), [0xFF, 1, 0, 2, 0xA5, 0x5A, 1, 0x43, 4, 0xF4])
        XCTAssertEqual(Array(DeviceCommand.band.packet(Wire.bandGain(at: 7, gain: 2.1)).encoded()), [0xFF, 1, 0, 2, 0xA5, 0x5A, 1, 0x43, 8, 21])
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
        state.firmware = "2.0.2"
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
    func testSingleBandReadbackUsesAndroidBandNumbers() {
        var state = DeviceState.demo
        state.bands = [-12, -6.1, -3.2, -1.3, 0, 0.1, 1.2, 3.4, 6.5, 12]
        // Android's EQ fragment sends seekbar IDs 1...10 unchanged to 0x0143.
        // Its local DSP/array uses ID - 1; preamp is seekbar ID 0.
        for (index, gain) in state.bands.enumerated() {
            let payload = [UInt8(index + 1), Wire.gain(gain)]
            XCTAssertEqual(Wire.bandGain(at: index, gain: gain), payload)
            XCTAssertTrue(DeviceCommand.band.matchesReadback(payload, state: state), DeviceState.bandLabels[index])
            XCTAssertFalse(DeviceCommand.band.matchesReadback([UInt8(index + 1), Wire.gain(gain == 12 ? gain - 0.1 : gain + 0.1)], state: state))
        }
        XCTAssertFalse(DeviceCommand.band.matchesReadback([0, 0], state: state))
        XCTAssertFalse(DeviceCommand.band.matchesReadback([11, 0], state: state))
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
        queue.enqueue(.init(command: .band, payload: [1, 10], key: "band-0"))
        queue.enqueue(.init(command: .band, payload: [2, 20], key: "band-1"))
        XCTAssertEqual(queue.inFlight?.token, first.token)
        XCTAssertEqual(queue.pending.count, 3)
        XCTAssertNil(queue.next())
        XCTAssertNil(queue.acknowledge(GAIAPacket(command: 0x8230, payload: [0]))) // unrelated notification
        XCTAssertNil(queue.acknowledge(GAIAPacket(command: 0x8110, payload: [0])))
        XCTAssertEqual(queue.beginReadback(for: first.token), .state)
        XCTAssertEqual(queue.acknowledge(GAIAPacket(command: 0x8010, payload: [0]))?.token, first.token)
        XCTAssertEqual(queue.next()?.payload, Wire.volume(-20))
    }
    func testEQWriteWithoutAcknowledgementCompletesOnReadback() {
        var queue = CommandQueue()
        queue.enqueue(.init(command: .eqEnabled, payload: [1]))
        let write = queue.next()!
        XCTAssertEqual(Array(write.packet.encoded()), [0xFF, 1, 0, 1, 0xA5, 0x5A, 1, 0x41, 1])
        XCTAssertEqual(queue.beginReadback(for: write.token), .eq)
        XCTAssertNil(queue.next())

        // Reproduces the physical ES100 2.0.2: no 0x8141, but 0x8050 reports EQ on.
        let reply = GAIAPacket(command: 0x8050, payload: [0, 1, 0] + Array(repeating: 0, count: 10))
        var actual = DeviceState()
        actual.firmware = "1.3.0"
        XCTAssertTrue(actual.apply(reply))
        XCTAssertEqual(queue.acknowledge(reply)?.token, write.token)
        XCTAssertTrue(write.command.matchesReadback(write.payload, state: actual))
        XCTAssertTrue(actual.eqEnabled)
        XCTAssertNil(queue.inFlight)
        XCTAssertNil(queue.inFlightReadback)
    }
    func testVolumeUsesStateReadbackWithoutRequiringWriteACK() {
        var queue = CommandQueue()
        queue.enqueue(.init(command: .volume, payload: Wire.volume(-21), key: "volume"))
        let write = queue.next()!
        XCTAssertEqual(write.command.confirmationReadback, .state)
        XCTAssertEqual(queue.beginReadback(for: write.token), .state)
        XCTAssertNil(queue.acknowledge(GAIAPacket(command: 0x8110, payload: [0])))
        XCTAssertEqual(queue.inFlight?.token, write.token)
        // A notification reports levels but is not the requested confirmation.
        XCTAssertNil(queue.acknowledge(GAIAPacket(command: 0x8230, payload: [0] + Wire.volume(-21) + Wire.volume(-18) + Wire.volume(-6))))
        XCTAssertEqual(queue.acknowledge(GAIAPacket(command: 0x8010, payload: [0]))?.token, write.token)
        XCTAssertNil(queue.inFlight)
    }
    func testVolumeReadbackComparesSignedFixedPointUnits() {
        var state = DeviceState.demo
        for volume in [-60.0, -32.5, -21, -0.5, 0, 6] {
            state.volume = volume
            XCTAssertTrue(DeviceCommand.volume.matchesReadback(Wire.volume(volume), state: state))
            XCTAssertFalse(DeviceCommand.volume.matchesReadback(Wire.volume(volume - 0.5), state: state))
        }
        XCTAssertFalse(DeviceCommand.volume.matchesReadback([], state: state))
        XCTAssertFalse(DeviceCommand.volume.matchesReadback([0], state: state))
    }
    func testOptionalWriteAcknowledgementDoesNotReplaceReadback() {
        for command: DeviceCommand in [.volume, .eqEnabled, .preamp, .band, .allGains, .headroom, .q] {
            var queue = CommandQueue()
            queue.enqueue(.init(command: command, payload: []))
            let write = queue.next()!
            let ack = GAIAPacket(command: command.rawValue | 0x8000, payload: [0])
            XCTAssertNil(queue.acknowledge(ack))
            XCTAssertEqual(queue.beginReadback(for: write.token), command.confirmationReadback)
            XCTAssertNil(queue.acknowledge(ack))
            XCTAssertEqual(queue.inFlight?.token, write.token)
            XCTAssertNil(queue.beginReadback(for: write.token)) // query only once
        }
    }
    func testEQReadbackMustBeRequestedAndBelongToCurrentTransaction() {
        var queue = CommandQueue()
        queue.enqueue(.init(command: .eqEnabled, payload: [1]))
        let write = queue.next()!
        let reply = GAIAPacket(command: 0x8050, payload: [0])
        XCTAssertNil(queue.acknowledge(reply)) // not yet requested
        XCTAssertNil(queue.beginReadback(for: UUID()))
        XCTAssertEqual(queue.beginReadback(for: write.token), .eq)
        XCTAssertNil(queue.acknowledge(GAIAPacket(command: 0x8230, payload: [0])))
        XCTAssertNil(queue.acknowledge(GAIAPacket(vendor: 1, command: 0x8050, payload: [0])))
        XCTAssertNil(queue.acknowledge(GAIAPacket(command: 0x0050, payload: [0])))
        XCTAssertNil(queue.acknowledge(GAIAPacket(command: 0x8050)))
        XCTAssertEqual(queue.inFlight?.token, write.token)
        queue.reset()
        queue.enqueue(.init(command: .eqEnabled, payload: [0]))
        _ = queue.next()
        XCTAssertNil(queue.beginReadback(for: write.token)) // cancelled work cannot send a query
        XCTAssertNil(queue.acknowledge(reply))
    }
    func testEQWriteAndReadbackErrorsCanFinishTransaction() {
        for replyID: UInt16 in [0x8141, 0x8050] {
            var queue = CommandQueue()
            queue.enqueue(.init(command: .eqEnabled, payload: [1]))
            let write = queue.next()!
            _ = queue.beginReadback(for: write.token)
            XCTAssertEqual(queue.acknowledge(GAIAPacket(command: replyID, payload: [1]))?.token, write.token)
            XCTAssertNil(queue.inFlight)
            XCTAssertNil(queue.inFlightReadback)
        }
        for replyID: UInt16 in [0x8110, 0x8010] {
            var queue = CommandQueue()
            queue.enqueue(.init(command: .volume, payload: Wire.volume(-21)))
            let write = queue.next()!
            _ = queue.beginReadback(for: write.token)
            XCTAssertEqual(queue.acknowledge(GAIAPacket(command: replyID, payload: [1]))?.token, write.token)
            XCTAssertNil(queue.inFlight)
        }
    }
    func testRapidEQEditsStaySerializedThroughReadback() {
        var queue = CommandQueue()
        queue.enqueue(.init(command: .eqEnabled, payload: [1], key: "eq"))
        let first = queue.next()!
        queue.enqueue(.init(command: .eqEnabled, payload: [0], key: "eq"))
        queue.enqueue(.init(command: .band, payload: [4, 10], key: "band-3"))
        queue.enqueue(.init(command: .band, payload: [4, 20], key: "band-3"))
        _ = queue.beginReadback(for: first.token)
        XCTAssertNil(queue.next())
        _ = queue.acknowledge(GAIAPacket(command: 0x8050, payload: [0]))
        let second = queue.next()!
        XCTAssertEqual(second.payload, [0])
        _ = queue.beginReadback(for: second.token)
        _ = queue.acknowledge(GAIAPacket(command: 0x8050, payload: [0]))
        XCTAssertEqual(queue.next()?.payload, [4, 20])
    }
    func testEQConfirmationChecksTheActualWireValues() {
        var state = DeviceState.demo
        state.bands[3] = -1.3
        let cases: [(DeviceCommand, [UInt8])] = [
            (.eqEnabled, [1]), (.preamp, [Wire.gain(state.preamp)]),
            (.band, [4, Wire.gain(-1.3000000000000003)]),
            (.allGains, ([state.preamp] + state.bands).map(Wire.gain)),
            (.headroom, [0x11]), (.q, Wire.u16(5791))
        ]
        for (command, payload) in cases {
            XCTAssertTrue(command.matchesReadback(payload, state: state), "\(command)")
            var wrong = payload; wrong[wrong.count - 1] ^= 1
            XCTAssertFalse(command.matchesReadback(wrong, state: state), "\(command)")
            XCTAssertFalse(command.matchesReadback([], state: state))
        }
        XCTAssertFalse(DeviceCommand.band.matchesReadback([0, 0], state: state))
        XCTAssertFalse(DeviceCommand.band.matchesReadback([11, 0], state: state))
        XCTAssertEqual(DeviceCommand.volume.confirmationReadback, .state)
        XCTAssertNil(DeviceCommand.eq.confirmationReadback)
    }
    func testFactoryPresetsMatchExtractedAndroidWireValues() {
        // Independent extracted 0x0144 payloads, after native initialization and
        // Java/UI rounding. Includes preamp, all 220 band values and signed gains.
        let expectedPayloads: [[UInt8]] = [
            [0x00, 0x18, 0x17, 0x14, 0x02, 0x08, 0x07, 0x11, 0x12, 0x11, 0x08], // Acoustic
            [0x00, 0x1B, 0x16, 0x10, 0x0E, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00], // Bass Booster
            [0x00, 0xE5, 0xEA, 0xF0, 0xF2, 0xFA, 0x00, 0x00, 0x00, 0x00, 0x00], // Bass Reducer
            [0x00, 0x17, 0x13, 0x0F, 0x0C, 0xF8, 0xF8, 0x00, 0x0F, 0x13, 0x17], // Classical
            [0x00, 0x13, 0x20, 0x18, 0x00, 0x09, 0x10, 0x18, 0x16, 0x10, 0x00], // Dance
            [0x00, 0x17, 0x12, 0x08, 0x04, 0x0F, 0x0D, 0x07, 0xF3, 0xEC, 0xE8], // Deep
            [0x00, 0x15, 0x13, 0x06, 0x00, 0xFA, 0x09, 0x02, 0x05, 0x13, 0x18], // Electronic
            [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], // FLAT
            [0x00, 0x18, 0x15, 0x06, 0x0E, 0xFA, 0xFA, 0x06, 0xFB, 0x09, 0x0E], // Hip-Hop
            [0x00, 0x13, 0x0F, 0x07, 0x09, 0xF9, 0xF9, 0x00, 0x07, 0x0F, 0x13], // Jazz
            [0x00, 0x16, 0x0F, 0x00, 0x00, 0xF8, 0xF8, 0xF8, 0x00, 0x0F, 0x16], // Latin
            [0x00, 0x1E, 0x13, 0x00, 0x00, 0xF7, 0x00, 0xFA, 0xE7, 0x18, 0x06], // Loudness
            [0x00, 0xF1, 0xF8, 0xFB, 0x07, 0x15, 0x0A, 0x00, 0xF8, 0x09, 0x05], // Lounge
            [0x00, 0x0F, 0x09, 0x00, 0x09, 0x0F, 0x07, 0x11, 0x16, 0x0F, 0x11], // Piano
            [0x00, 0xF8, 0xFA, 0x00, 0x09, 0x14, 0x14, 0x09, 0x00, 0xFA, 0xF8], // Pop
            [0x00, 0x0E, 0x23, 0x1D, 0x07, 0xF4, 0xF9, 0x0C, 0x0D, 0x0F, 0x13], // R&B
            [0x00, 0x19, 0x14, 0x0F, 0x06, 0xFD, 0xFA, 0x01, 0x0C, 0x11, 0x15], // Rock
            [0x00, 0x1A, 0x15, 0x14, 0x0B, 0x06, 0x00, 0xFA, 0xF5, 0xEC, 0xEA], // Small Speakers
            [0x00, 0xEC, 0xFB, 0x00, 0x05, 0x11, 0x17, 0x17, 0x16, 0x0C, 0x00], // Spoken Word
            [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x0A, 0x10, 0x16, 0x19], // Treble Booster
            [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF9, 0xF6, 0xF0, 0xEA, 0xE7], // Treble Reducer
            [0x00, 0xF8, 0xF1, 0xF1, 0x07, 0x12, 0x12, 0x0F, 0x07, 0x00, 0xF8], // Vocal Booster
        ]
        XCTAssertEqual(FactoryEQPreset.all.map(\.id), Array(0..<22))
        XCTAssertEqual(FactoryEQPreset.all.map { ([$0.preamp] + $0.bands).map(Wire.gain) }, expectedPayloads)
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

