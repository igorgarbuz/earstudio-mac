import EarStudioCore

/// Literal fixtures transcribed from Android GaiaCommandManager's decoders.
/// These deliberately do not use our command encoders to construct readbacks.
public enum ControlFixtures {
    public static let details: [UInt8] = [0, 0, 0, 0, 1, 0, 2, 0, 2, 0xE7, 0x80, 1, 0x0B, 0x83, 0xE2, 0xC0]
    public static let info: [UInt8] = [0, 7, 1, 0xE4, 0xFE, 0x80, 0xFD, 0, 3, 0, 4]
    public static let audio: [UInt8] = [0, 82, 0xC5, 0x82, 0xB4, 0xF9, 0xC1, 0xDF, 0x80, 0xEE, 0, 0xFA, 0, 0x8B, 0xED, 75]
    public static let eq: [UInt8] = [0, 1, 0xE2, 0xC4, 0xD8, 0xEC, 0, 10, 30, 50, 20, 40, 60, 0x12, 0x0B, 0x50]
    public static var state: DeviceState {
        var state = DeviceState()
        for (id, payload): (UInt16, [UInt8]) in [(0x8000, details), (0x8001, info), (0x8010, audio), (0x8050, eq)] {
            precondition(state.apply(GAIAPacket(command: id, payload: payload)))
        }
        return state
    }
    // Every setting exposed by the UI, with independent expected wire payloads.
    public static let settings: [(DeviceCommand, [UInt8], DeviceCommand)] = [
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

