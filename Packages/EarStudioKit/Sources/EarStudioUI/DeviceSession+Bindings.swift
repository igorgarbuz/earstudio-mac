import SwiftUI
import EarStudioCore
import EarStudioSession

public extension DeviceSession {
    func doubleBinding(_ path: WritableKeyPath<DeviceState, Double>, _ command: DeviceCommand, range: ClosedRange<Double>, gain: Bool = false) -> Binding<Double> {
        Binding(get: { self.state[keyPath: path] }, set: { value in
            guard value.isFinite else { return }
            var value = min(range.upperBound, max(range.lowerBound, value))
            if command == .volume, self.state.supportsHeadroom, self.state.loaded.contains(.info) { value = min(value, self.state.volumeLimit) }
            self.change(command, payload: gain ? [Wire.gain(value)] : Wire.volume(value)) { $0[keyPath: path] = value }
            if command == .preamp { self.presetName = "Custom" }
        })
    }
    func boolBinding(_ path: WritableKeyPath<DeviceState, Bool>, _ command: DeviceCommand) -> Binding<Bool> {
        Binding(get: { self.state[keyPath: path] }, set: { value in
            self.change(command, payload: [value ? 1 : 0]) { $0[keyPath: path] = value }
        })
    }
    func intBinding(_ path: WritableKeyPath<DeviceState, Int>, _ command: DeviceCommand, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { self.state[keyPath: path] }, set: { value in
            let value = min(range.upperBound, max(range.lowerBound, value))
            self.change(command, payload: [UInt8(value)]) { $0[keyPath: path] = value }
        })
    }
    func bandBinding(_ index: Int) -> Binding<Double> {
        Binding(get: { self.state.bands[index] }, set: { value in
            guard value.isFinite else { return }
            let value = (min(12, max(-12, value)) * 10).rounded() / 10
            self.change(.band, payload: Wire.bandGain(at: index, gain: value), key: "band-\(index)") { $0.bands[index] = value }
            self.presetName = "Custom"
        })
    }
}
