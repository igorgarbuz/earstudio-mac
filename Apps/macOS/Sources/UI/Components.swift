import EarStudioCore
import EarStudioSession
import EarStudioUI
import SwiftUI

struct Panel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !title.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
            content
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(StudioTheme.border))
    }
}

struct SettingToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var value: Bool
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel(title)
        }
    }
}

struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step = 0.5
    var unit = "dB"
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(step < 0.1 ? 2 : (step < 1 ? 1 : 0)))) + (unit.isEmpty ? "" : " " + unit))
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(StudioTheme.green)
            }
            Slider(value: $value.quantized(step), in: range).controlSize(.small).accessibilityLabel(title)
        }
    }
}

extension Binding where Value == Double {
    func quantized(_ step: Double) -> Binding<Double> {
        Binding(get: { wrappedValue }, set: { wrappedValue = ($0 / step).rounded() * step })
    }
}

struct IntegerSlider: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Double = 1
    var unit = ""
    var body: some View {
        ValueSlider(title: title, value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                    range: Double(range.lowerBound)...Double(range.upperBound), step: step, unit: unit)
    }
}

extension ConnectionPhase {
    var statusColor: Color {
        self == .connected ? StudioTheme.green : .orange
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10, weight: .semibold)).tracking(0.4)
        }.foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.09), in: Capsule())
    }
}

struct AudioInputStatus: View {
    let state: DeviceState?

    private var activeSlot: Int? {
        guard let input = state?.input, input == 2 || input == 3 else { return nil }
        return input - 1
    }
    private var detail: String {
        if let activeSlot { return "Source \(activeSlot) is active" }
        switch state?.input {
        case nil: return "No device connected"
        case 0: return "No active audio input"
        case 1: return "Audio over USB"
        default: return "Audio input unavailable"
        }
    }
    private var help: String {
        if let activeSlot {
            return "ES100 has two Bluetooth source slots. Slot \(activeSlot) is the active audio input. The other slot may still be connected. These indicators show status; change playback on the source device to switch inputs."
        }
        return detail
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 8) {
                if let activeSlot {
                    if let icon = NSImage(named: NSImage.bluetoothTemplateName) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 12, height: 16)
                            .foregroundStyle(StudioTheme.secondary)
                    }
                    Text("Bluetooth")
                    HStack(spacing: 4) {
                        ForEach(1...2, id: \.self) { slot in
                            HStack(spacing: 3) {
                                if slot == activeSlot { Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)) }
                                Text("\(slot)").monospacedDigit()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: slot == activeSlot ? 32 : 24, height: 24)
                            .foregroundStyle(slot == activeSlot ? StudioTheme.green : StudioTheme.secondary)
                            .background(slot == activeSlot ? StudioTheme.green.opacity(0.12) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    Text(state?.inputName ?? "ES100 / MK2")
                }
            }.font(.system(size: 12, weight: .medium)).frame(height: 24)
            Text(detail).font(.system(size: 10)).foregroundStyle(StudioTheme.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activeSlot == nil ? "\(state?.inputName ?? "ES100 / MK2"). \(detail)" : "Bluetooth. \(detail)")
        .help(help)
    }
}

struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(StudioTheme.secondary)
            Text(value).font(.system(size: 16, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func sectionCaption() -> some View {
        self.font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(StudioTheme.secondary)
    }
}
