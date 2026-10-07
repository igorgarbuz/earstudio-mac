import Foundation

/// GAIA v1 framing recovered from EarStudio Android 1.9.0.
/// Vendor payloads, including asynchronous notifications, start with a status byte.
struct GAIAPacket: Equatable {
    static let earStudioVendor: UInt16 = 0xA55A
    var vendor: UInt16 = earStudioVendor
    var command: UInt16
    var payload: [UInt8] = []
    var flags: UInt8 = 0

    var id: UInt16 { command & 0x7FFF }
    var isAcknowledgement: Bool { command & 0x8000 != 0 }
    var status: UInt8? { payload.first }

    func encoded() -> Data {
        precondition(payload.count <= 254)
        var bytes: [UInt8] = [0xFF, 1, flags, UInt8(payload.count)]
        bytes += Wire.u16(vendor) + Wire.u16(command) + payload
        if flags & 1 != 0 { bytes.append(bytes.reduce(0, ^)) }
        return Data(bytes)
    }
}

/// RFCOMM is a byte stream: reads can split or combine any number of frames.
struct GAIAStreamDecoder {
    private var buffer: [UInt8] = []
    private(set) var rejectedFrames = 0

    mutating func reset() { buffer.removeAll(); rejectedFrames = 0 }

    mutating func append(_ data: Data) -> [GAIAPacket] {
        buffer.append(contentsOf: data)
        var packets: [GAIAPacket] = []
        while !buffer.isEmpty {
            guard let start = buffer.firstIndex(of: 0xFF) else {
                buffer.removeAll(); break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 4 else { break }
            guard buffer[1] == 1, buffer[2] & 0xFE == 0, buffer[3] <= 254 else {
                buffer.removeFirst(); rejectedFrames += 1; continue
            }
            let length = 8 + Int(buffer[3]) + (buffer[2] & 1 == 1 ? 1 : 0)
            guard buffer.count >= length else { break }
            let frame = Array(buffer.prefix(length))
            if frame[2] & 1 != 0, frame.reduce(0, ^) != 0 {
                buffer.removeFirst(); rejectedFrames += 1; continue
            }
            packets.append(GAIAPacket(
                vendor: Wire.readU16(frame, 4), command: Wire.readU16(frame, 6),
                payload: Array(frame[8..<(8 + Int(frame[3]))]), flags: frame[2]
            ))
            buffer.removeFirst(length)
        }
        return packets
    }
}

enum Wire {
    static func u16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 255)] }
    static func readU16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
    static func volume(_ value: Double) -> [UInt8] {
        let safe = value.isFinite ? min(127.996, max(-128, value)) : -60
        return u16(UInt16(bitPattern: Int16((safe * 256).rounded(.towardZero))))
    }
    static func readVolume(_ bytes: [UInt8], _ offset: Int) -> Double {
        Double(Int16(bitPattern: readU16(bytes, offset))) / 256
    }
    /// Java Math.round rounds negative half values toward positive infinity.
    static func gain(_ value: Double) -> UInt8 {
        let safe = value.isFinite ? min(12, max(-12, value)) : 0
        return UInt8(bitPattern: Int8(floor(safe * 10 + 0.5)))
    }
    static func readGain(_ byte: UInt8) -> Double { Double(Int8(bitPattern: byte)) / 10 }
}

enum DeviceCommand: UInt16 {
    case deviceInfo = 0x0001, state = 0x0010, eq = 0x0050, battery = 0x0070
    case dct = 0x0102
    case volume = 0x0110, mute = 0x0111, toneVolume = 0x0112, callMute = 0x0113
    case trim = 0x0114, volumeLimit = 0x0115
    case crossfeed = 0x0120, oversampling = 0x0121, dacFilter = 0x0123, jitter = 0x0125
    case batteryInterval = 0x0130
    case eqEnabled = 0x0141, preamp = 0x0142, band = 0x0143, allGains = 0x0144
    case headroom = 0x0145, q = 0x0146
    case charger = 0x0151, autoPower = 0x0153, batteryCare = 0x0157, reconnect = 0x0158
    case outputMode = 0x0160, outputLock = 0x0161, codecs = 0x0162, buffer = 0x0163
    case mic = 0x0170, loopback = 0x0171, hfp = 0x0172
    case ambient = 0x0180, ambientMic = 0x0181, ambientRatio = 0x0182, ambientShortcut = 0x0183
    case led = 0x0190, usbBits = 0x01A0
    case authenticate = 0x0300, cancelAuthentication = 0x0301

    func packet(_ payload: [UInt8] = []) -> GAIAPacket {
        GAIAPacket(command: rawValue, payload: payload)
    }
    var isRead: Bool { [.deviceInfo, .state, .eq, .battery].contains(self) }
    func supported(by state: DeviceState) -> Bool {
        // Minimum versions explicitly checked by the Android controls.
        switch self {
        case .q: return state.supportsQ
        case .usbBits, .headroom, .volumeLimit, .reconnect, .hfp: return state.supportsHeadroom
        case .trim: return state.firmwareAtLeast(1, 3, 1)
        case .batteryCare: return state.firmwareAtLeast(1, 2, 4)
        case .led: return state.firmwareAtLeast(1, 2, 2)
        case .buffer: return state.firmwareAtLeast(1, 2, 1)
        case .toneVolume: return state.firmwareAtLeast(1, 1, 3)
        default: return true
        }
    }
    var refresh: DeviceCommand? {
        switch self {
        case .eqEnabled, .preamp, .band, .allGains, .headroom, .q: return .eq
        case .trim, .volumeLimit, .buffer, .led, .usbBits, .hfp, .batteryCare, .reconnect: return .deviceInfo
        case .authenticate, .cancelAuthentication, .deviceInfo, .state, .eq, .battery, .batteryInterval: return nil
        default: return .state
        }
    }
}

/// Coalesce unsent slider updates, but never replace a command already in flight.
struct CommandQueue {
    struct Item {
        var token = UUID()
        var command: DeviceCommand
        var payload: [UInt8]
        var key: String?
        var packet: GAIAPacket { command.packet(payload) }
    }
    private(set) var pending: [Item] = []
    private(set) var inFlight: Item?

    mutating func enqueue(_ item: Item) {
        if let key = item.key, let index = pending.firstIndex(where: { $0.key == key }) {
            pending[index] = item
        } else { pending.append(item) }
    }
    mutating func next() -> Item? {
        guard inFlight == nil, !pending.isEmpty else { return nil }
        inFlight = pending.removeFirst()
        return inFlight
    }
    mutating func acknowledge(_ id: UInt16) -> Item? {
        guard inFlight?.command.rawValue == id else { return nil }
        defer { inFlight = nil }
        return inFlight
    }
    mutating func reset() { pending.removeAll(); inFlight = nil }
}
