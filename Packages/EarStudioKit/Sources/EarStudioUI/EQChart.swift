import SwiftUI
import EarStudioCore

public struct EQChart: View {
    public init(state: DeviceState, active: Bool) { self.state = state; self.active = active }
    let state: DeviceState
    var active: Bool
    public var body: some View {
        Canvas { context, size in
            let left = 30.0, right = size.width - 12, top = 9.0, bottom = size.height - 23
            func x(_ frequency: Double) -> Double { left + log10(frequency / 20) / 3 * (right - left) }
            func y(_ gain: Double) -> Double { top + (15 - min(15, max(-15, gain))) / 30 * (bottom - top) }
            for gain in [-12, -6, 0, 6, 12] {
                var line = Path(); line.move(to: CGPoint(x: left, y: y(Double(gain)))); line.addLine(to: CGPoint(x: right, y: y(Double(gain))))
                context.stroke(line, with: .color(.white.opacity(gain == 0 ? 0.16 : 0.055)), style: StrokeStyle(lineWidth: 1, dash: gain == 0 ? [] : [3, 4]))
                context.draw(Text(gain > 0 ? "+\(gain)" : "\(gain)").font(.system(size: 8)).foregroundColor(StudioTheme.secondary), at: CGPoint(x: 13, y: y(Double(gain))))
            }
            for frequency in [31.5, 125, 500, 2000, 8000, 16000] {
                var line = Path(); line.move(to: CGPoint(x: x(frequency), y: top)); line.addLine(to: CGPoint(x: x(frequency), y: bottom))
                context.stroke(line, with: .color(.white.opacity(0.045)), lineWidth: 1)
                let label = frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
                context.draw(Text(label).font(.system(size: 8)).foregroundColor(StudioTheme.secondary), at: CGPoint(x: x(frequency), y: size.height - 6))
            }
            var curve = Path()
            for index in 0...240 {
                let f = 20 * pow(1000, Double(index) / 240)
                let db = active ? EQResponse.decibels(at: f, gains: state.bands, preamp: state.preamp, q: state.q == 2896 ? 0.7071 : 1.4142) : 0
                let point = CGPoint(x: x(f), y: y(db))
                if index == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            var fill = curve; fill.addLine(to: CGPoint(x: right, y: bottom)); fill.addLine(to: CGPoint(x: left, y: bottom)); fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [StudioTheme.green.opacity(active ? 0.2 : 0.02), .clear]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
            context.stroke(curve, with: .color(active ? StudioTheme.green : StudioTheme.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }.accessibilityLabel(active ? "Estimated equalizer response curve" : "Equalizer bypassed")
    }
}
