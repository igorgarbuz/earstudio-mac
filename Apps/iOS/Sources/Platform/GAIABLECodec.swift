import Foundation
import EarStudioCore

/// GAIA BLE v1 uses an ATT value containing vendor, command, then payload. It
/// does not carry the RFCOMM start/version/flags/length header or XOR checksum.
/// Reference: Qualcomm GaiaPacketBLE.java, GAIAControl fb9a492e783172041cc53eeb41143a7ad00eb212.
enum GAIABLECodec {
    static let serviceUUID = "00001100-D102-11E1-9B23-00025B00A5A5"
    static let commandUUID = "00001101-D102-11E1-9B23-00025B00A5A5"
    static let responseUUID = "00001102-D102-11E1-9B23-00025B00A5A5"
    static let dataUUID = "00001103-D102-11E1-9B23-00025B00A5A5"
    static let maximumCommandPayloadLength = 16
    // Qualcomm bounds outbound commands at 16 bytes, but its receive constructor
    // accepts larger characteristic values after MTU negotiation. Preserve those
    // replies up to the shared stream codec's representable payload length.
    static let maximumResponsePayloadLength = 254

    static func encode(streamFrame: Data) -> Data? {
        var decoder = GAIAStreamDecoder()
        let packets = decoder.append(streamFrame)
        guard packets.count == 1, let packet = packets.first,
              packet.encoded() == streamFrame,
              packet.vendor == GAIAPacket.earStudioVendor,
              packet.payload.count <= maximumCommandPayloadLength else { return nil }
        return Data(Wire.u16(packet.vendor) + Wire.u16(packet.command) + packet.payload)
    }

    static func decode(characteristicValue: Data) -> Data? {
        let bytes = [UInt8](characteristicValue)
        guard (4...(4 + maximumResponsePayloadLength)).contains(bytes.count),
              Wire.readU16(bytes, 0) == GAIAPacket.earStudioVendor else { return nil }
        return GAIAPacket(vendor: Wire.readU16(bytes, 0), command: Wire.readU16(bytes, 2),
                          payload: Array(bytes.dropFirst(4))).encoded()
    }
}
