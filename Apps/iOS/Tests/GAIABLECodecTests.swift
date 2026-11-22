import XCTest
import EarStudioCore
@testable import EarStudioIOS

final class GAIABLECodecTests: XCTestCase {
    func testAuthenticationAndSingleBandCommandUseBLEFraming() {
        let authentication = Data([0xFF, 1, 0, 2, 0xA5, 0x5A, 3, 0, 0x12, 0x34])
        XCTAssertEqual(GAIABLECodec.encode(streamFrame: authentication), Data([0xA5, 0x5A, 3, 0, 0x12, 0x34]))
        let band = Data([0xFF, 1, 0, 2, 0xA5, 0x5A, 1, 0x43, 8, 21])
        XCTAssertEqual(GAIABLECodec.encode(streamFrame: band), Data([0xA5, 0x5A, 1, 0x43, 8, 21]))
    }

    func testReadbackPreservesVendorAcknowledgementStatusAndSignedBytes() throws {
        let ble = Data([0xA5, 0x5A, 0x80, 0x01, 0, 7, 1, 0xE4, 0xFE, 0x80, 0xFD, 0, 3, 0, 4])
        let stream = try XCTUnwrap(GAIABLECodec.decode(characteristicValue: ble))
        XCTAssertEqual(stream, Data([0xFF, 1, 0, 11, 0xA5, 0x5A, 0x80, 0x01, 0, 7, 1, 0xE4, 0xFE, 0x80, 0xFD, 0, 3, 0, 4]))
        var decoder = GAIAStreamDecoder()
        let reply = try XCTUnwrap(decoder.append(stream).first)
        XCTAssertEqual(reply.vendor, 0xA55A)
        XCTAssertTrue(reply.isAcknowledgement)
        XCTAssertEqual(reply.status, 0)
    }

    func testRejectsTruncatedForeignOversizeAndCombinedPackets() {
        XCTAssertNil(GAIABLECodec.decode(characteristicValue: Data([0xA5, 0x5A, 0x80])))
        XCTAssertNil(GAIABLECodec.decode(characteristicValue: Data([0, 0x0A, 0x80, 0, 0])))
        XCTAssertNil(GAIABLECodec.decode(characteristicValue: Data([0xA5, 0x5A, 0x80, 0] + Array(repeating: 0, count: 255))))
        let frame = GAIAPacket(command: 0x0010).encoded()
        XCTAssertNil(GAIABLECodec.encode(streamFrame: frame + frame))
        XCTAssertNil(GAIABLECodec.encode(streamFrame: frame.dropLast()))
        XCTAssertNil(GAIABLECodec.encode(streamFrame: GAIAPacket(command: 0x0010, payload: Array(repeating: 0, count: 17)).encoded()))
    }

    func testExtendedResponseFromLargerMTUPreservesAdditionalFirmwareFields() throws {
        let payload: [UInt8] = [0, 0, 0, 0, 1, 0, 2, 0, 2, 0xE7, 0x80, 1, 0x0B, 0x83, 0xE2, 0xC0, 0x42]
        let stream = try XCTUnwrap(GAIABLECodec.decode(characteristicValue: Data([0xA5, 0x5A, 0x80, 0] + payload)))
        var decoder = GAIAStreamDecoder()
        XCTAssertEqual(decoder.append(stream).first?.payload, payload)
        // The receive allowance must not silently broaden outbound commands.
        XCTAssertNil(GAIABLECodec.encode(streamFrame: GAIAPacket(command: 0x0010, payload: payload).encoded()))
    }

    func testFullSizeEQReplyRemainsOnePacket() throws {
        let ble = Data([0xA5, 0x5A, 0x80, 0x50, 0, 1, 0xE2, 0xC4, 0xD8, 0xEC, 0, 10, 30, 50, 20, 40, 60, 0x12, 0x0B, 0x50])
        let stream = try XCTUnwrap(GAIABLECodec.decode(characteristicValue: ble))
        XCTAssertEqual(GAIABLECodec.encode(streamFrame: stream), ble)
    }

    func testDiscoveryDoesNotOfferUnrelatedGAIADevices() {
        XCTAssertTrue(IOSStudioModel.isEarStudioName("EarStudio"))
        XCTAssertTrue(IOSStudioModel.isEarStudioName("ES100 MK2"))
        XCTAssertFalse(IOSStudioModel.isEarStudioName("Other GAIA headset"))
        XCTAssertFalse(IOSStudioModel.isEarStudioName(""))
    }
}
