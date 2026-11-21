import Foundation

public enum StateGroup: Hashable { case device, info, audio, eq, battery }

public struct DeviceState: Equatable {
    public init() {}

    public var firmware: String?
    public var battery = 0
    public var millivolts = 0
    public var charging = false
    public var chargerConnected = false
    public var chargerEnabled = true
    public var batteryCare = false
    public var autoPower = 0
    public var input = 0
    public var codec = 0
    public var sampleRate = 0
    public var bits = 0
    public var volume = -40.0
    public var callVolume = -40.0
    public var usbVolume = -40.0
    public var callActive = false
    public var muted = false
    public var callMuted = false
    public var toneVolume = -24.0
    public var leftTrim = 0.0
    public var rightTrim = 0.0
    public var volumeLimit = 0.0
    public var eqEnabled = false
    public var preamp = 0.0
    public var bands = Array(repeating: 0.0, count: 10)
    public var headroom = 1
    public var analogCompensation = true
    public var q = 5791
    public var crossfeed = 0
    public var dct = 0
    public var dctEnabled = false
    public var oversampling = 0
    public var dacFilter = 0
    public var outputMode = 0
    public var outputLocked = false
    public var jitterUSB = false
    public var jitterBluetooth = false
    public var aac = true
    public var aptx = true
    public var aptxHD = true
    public var buffer = 7
    public var led = 0
    public var usbBits = 0
    public var reconnect = true
    public var micPreamp = false
    public var micGain = 11
    public var loopback = -24.0
    public var hfp = 0
    public var ambient = false
    public var ambientPreamp = false
    public var ambientGain = 11
    public var ambientRatio = 50
    public var ambientShortcut = true
    public var loaded: Set<StateGroup> = []

    public static let frequencies = [31.5, 63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000.0]
    public static let bandLabels = ["31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    // Android com.radsone.earstudio.d.l.a: the wire value is an index,
    // not a linear dB gain. The microphone preamp adds 21 dB.
    public static let micGains = [-27.0, -23.5, -21, -17.5, -15, -11.5, -9, -5.5, -3, 0, 3, 6, 9, 12, 15, 18, 21.5, 24, 27.5, 30, 33.5, 36, 39.5]
    public func microphoneDecibels(ambient: Bool) -> Double {
        let index = ambient ? ambientGain : micGain
        return (Self.micGains.value(at: index) ?? 0) + ((ambient ? ambientPreamp : micPreamp) ? 21 : 0)
    }
    public var codecName: String { ["SBC", "AAC", "aptX", "aptX HD", "LDAC"].value(at: codec) ?? "Unknown" }
    public var inputName: String { ["Idle", "USB DAC", "Bluetooth 1", "Bluetooth 2"].value(at: input) ?? "Unknown" }
    public var rateName: String { ["44.1 kHz", "48 kHz", "88.2 kHz", "96 kHz"].value(at: sampleRate) ?? "—" }
    public var bitsName: String { bits == 0 ? "16-bit" : "24-bit" }
    public var outputName: String { outputMode < 2 ? "3.5 mm · Unbalanced" : "2.5 mm · Balanced" }
    public var supportsQ: Bool { firmwareAtLeast(1, 4, 3) }
    public var supportsHeadroom: Bool { firmwareAtLeast(1, 4, 0) }
    public func firmwareAtLeast(_ major: Int, _ minor: Int, _ patch: Int) -> Bool {
        guard let v = firmware?.split(separator: ".").compactMap({ Int($0) }), v.count == 3 else { return false }
        return !v.lexicographicallyPrecedes([major, minor, patch])
    }

    /// Offsets include the status byte, exactly as in Android GaiaCommandManager.
    /// A truncated response never partially mutates the associated state.
    @discardableResult
    public mutating func apply(_ packet: GAIAPacket) -> Bool {
        guard packet.vendor == GAIAPacket.earStudioVendor, packet.isAcknowledgement, packet.status == 0 else { return false }
        let b = packet.payload
        func bit(_ index: Int, _ mask: UInt8) -> Bool { b[index] & mask != 0 }
        switch packet.id {
        case 0x0000:
            guard b.count >= 11 else { return false }
            firmware = "\(b[6]).\(b[7]).\(b[8])"
            toneVolume = Wire.readVolume(b, 9)
            if b.count >= 13 {
                aac = bit(12, 2); aptx = bit(12, 4); aptxHD = bit(12, 8)
            }
            if b.count >= 16 {
                autoPower = bit(13, 128) ? 1 : (bit(13, 64) ? 2 : 0)
                crossfeed = Int(b[13] & 15); loopback = Wire.readVolume(b, 14)
            }
            // Short legacy/startup packets establish firmware, but must not
            // enable controls whose fields were absent from that packet.
            if b.count >= 16 { loaded.insert(.device) }
        case 0x0001:
            guard firmware != nil else { return false }
            let required = supportsQ ? 11 : (supportsHeadroom ? 10 : (firmwareAtLeast(1, 3, 1) ? 8 : (firmwareAtLeast(1, 2, 4) ? 4 : 3)))
            guard b.count >= required else { return false }
            buffer = Int(b[1] & 15); led = Int(b[2] & 15)
            if firmwareAtLeast(1, 2, 4) { batteryCare = bit(3, 128); codec = Int(b[3] & 15) }
            if firmwareAtLeast(1, 3, 1) { leftTrim = Wire.readVolume(b, 4); rightTrim = Wire.readVolume(b, 6) }
            if supportsHeadroom {
                reconnect = bit(3, 64); hfp = Int((b[3] >> 5) & 1)
                volumeLimit = Wire.readVolume(b, 8)
                if !supportsQ { usbBits = Int((b[3] >> 4) & 1) }
            }
            if supportsQ { usbBits = Int((b[10] >> 1) & 3) }
            loaded.insert(.info)
        case 0x0010:
            guard b.count >= 16 else { return false }
            battery = min(100, Int(b[1] & 127))
            dctEnabled = bit(2, 128); oversampling = Int((b[2] >> 5) & 3); dct = Int(b[2] & 15)
            dacFilter = Int(b[3] & 3)
            callActive = bit(3, 128)
            input = Int((b[4] >> 6) & 3)
            jitterUSB = bit(4, 16); jitterBluetooth = bit(4, 32)
            sampleRate = Int((b[4] >> 2) & 3)
            if !firmwareAtLeast(1, 2, 4) { codec = Int(b[4] & 3) }
            muted = bit(5, 128); callMuted = bit(5, 64)
            chargerConnected = bit(5, 32); charging = bit(5, 16)
            bits = Int((b[5] >> 3) & 1); chargerEnabled = bit(5, 1)
            decodeOutput(b[6])
            volume = Wire.readVolume(b, 7)
            callVolume = Wire.readVolume(b, 9)
            usbVolume = Wire.readVolume(b, 11)
            micPreamp = bit(13, 128); micGain = Int(b[13] & 31)
            decodeAmbient(b[14], b[15])
            loaded.formUnion([.audio, .battery])
        case 0x0050:
            guard firmware != nil else { return false }
            guard b.count >= (supportsQ ? 16 : (supportsHeadroom ? 14 : 13)) else { return false }
            eqEnabled = b[1] != 0; preamp = Wire.readGain(b[2])
            bands = b[3..<13].map(Wire.readGain)
            if supportsHeadroom { headroom = Int(b[13] & 15); analogCompensation = bit(13, 16) }
            if supportsQ { q = Int(Wire.readU16(b, 14)) }
            loaded.insert(.eq)
        case 0x0070, 0x0200:
            guard b.count >= 4 else { return false }
            battery = min(100, Int(b[1])); millivolts = Int(Wire.readU16(b, 2)); loaded.insert(.battery)
        case 0x0202:
            guard b.count >= 2 else { return false }; charging = b[1] != 0
        case 0x0220:
            guard b.count >= 8 else { return false }
            input = Int(b[1]); volume = Wire.readVolume(b, 2); callVolume = Wire.readVolume(b, 4); usbVolume = Wire.readVolume(b, 6)
        case 0x0221:
            guard b.count >= 2 else { return false }; decodeOutput(b[1])
        case 0x0222:
            guard b.count >= 5 else { return false }
            sampleRate = Int(b[1]); codec = Int(b[2]); bits = Int(b[3]); oversampling = Int(b[4])
        case 0x0230:
            guard b.count >= 7 else { return false }
            volume = Wire.readVolume(b, 1); callVolume = Wire.readVolume(b, 3); usbVolume = Wire.readVolume(b, 5)
        case 0x0231:
            guard b.count >= 2 else { return false }; muted = bit(1, 16); callMuted = bit(1, 1)
        case 0x0232:
            guard b.count >= 3 else { return false }; decodeAmbient(b[1], b[2])
        case 0x0250:
            guard b.count >= 2 else { return false }; callActive = b[1] & 15 != 0
        case 0x0040:
            guard b.count >= 2 else { return false }; crossfeed = Int(b[1])
        case 0x0041:
            guard b.count >= 2 else { return false }; oversampling = Int(b[1])
        case 0x0043:
            guard b.count >= 2 else { return false }; dacFilter = Int(b[1])
        default: return false
        }
        return true
    }
    private mutating func decodeAmbient(_ flags: UInt8, _ ratio: UInt8) {
        ambient = flags & 128 != 0; ambientPreamp = flags & 64 != 0
        ambientShortcut = flags & 32 != 0; ambientGain = Int(flags & 31); ambientRatio = Int(ratio)
    }
    private mutating func decodeOutput(_ value: UInt8) {
        // Android maps mode bit0 and gain bits6/5 to its four output choices.
        let singleEnded = value & 1 != 0
        let high = value & (singleEnded ? 64 : 32) != 0
        outputMode = (singleEnded ? 0 : 2) + (high ? 1 : 0)
        outputLocked = value & 128 != 0
    }
    public static var demo: DeviceState {
        var s = DeviceState()
        s.firmware = "2.0.2"; s.battery = 82; s.millivolts = 4020
        s.input = 2; s.codec = 1; s.sampleRate = 1; s.bits = 1
        s.volume = -32; s.usbVolume = -32; s.eqEnabled = true; s.preamp = -3
        s.bands = [3, 2.5, 1.5, 0, -1, -0.5, 1, 2, 1.5, 0.5]
        s.crossfeed = 3; s.oversampling = 1
        s.loaded = [.device, .info, .audio, .eq, .battery]
        return s
    }
}

extension Array {
    func value(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
