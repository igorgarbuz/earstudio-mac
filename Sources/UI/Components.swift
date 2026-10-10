import SwiftUI

enum StudioTheme {
    static let green = Color(red: 133/255, green: 243/255, blue: 75/255)
    static let background = Color(red: 16/255, green: 18/255, blue: 18/255)
    static let sidebar = Color(red: 20/255, green: 23/255, blue: 22/255)
    static let card = Color(red: 25/255, green: 29/255, blue: 28/255)
    static let secondary = Color(red: 149/255, green: 160/255, blue: 154/255)
    static let border = Color.white.opacity(0.075)
}

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

struct DeviceImage: View {
    var body: some View {
        // The same unchanged Android product photo used in the README.
        // Attribution and licensing are recorded in Docs/Provenance.md.
        Image("ES100Product")
            .resizable()
            .scaledToFit()
            .frame(width: 220, height: 235)
            .accessibilityLabel("EarStudio ES100 product photo")
    }
}

extension View {
    func sectionCaption() -> some View {
        self.font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(StudioTheme.secondary)
    }
}
