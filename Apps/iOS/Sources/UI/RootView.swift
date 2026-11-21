import SwiftUI
import EarStudioCore
import EarStudioSession
import EarStudioUI

struct RootView: View {
    @EnvironmentObject private var model: IOSStudioModel

    @State private var selection: String = {
        let value = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--screenshot-tab=") }?.split(separator: "=").last.map(String.init)
        return value == "equalizer" || value == "settings" ? value! : "device"
    }()

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { PhoneDeviceView() }
                .tabItem { Label("Device", systemImage: "hifispeaker") }
                .tag("device")
                .accessibilityIdentifier("tab.device")
            NavigationStack { PhoneEqualizerView() }
                .tabItem { Label("Equalizer", systemImage: "slider.vertical.3") }
                .tag("equalizer")
                .accessibilityIdentifier("tab.equalizer")
            NavigationStack { PhoneSettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag("settings")
                .accessibilityIdentifier("tab.settings")
        }
        .tint(StudioTheme.green)
        .preferredColorScheme(.dark)
    }
}

struct SessionMessageSection: View {
    @EnvironmentObject private var model: IOSStudioModel
    var body: some View {
        if let message = model.session.message {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "info.circle")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss") { model.session.message = nil }
                        .frame(minHeight: 44)
                }
            }
        }
    }
}

/// Vertical labels and native sliders remain readable on small screens and at
/// accessibility text sizes. Values are also exposed to VoiceOver.
struct PhoneSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.5
    var unit = "dB"
    var identifier = ""
    var compact = false

    private var formatted: String {
        value.formatted(.number.precision(.fractionLength(step < 0.1 ? 2 : (step < 1 ? 1 : 0)))) + (unit.isEmpty ? "" : " " + unit)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title).fixedSize()
                    Spacer(minLength: 12)
                    Text(formatted).monospacedDigit().foregroundStyle(StudioTheme.green).fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(formatted).monospacedDigit().foregroundStyle(StudioTheme.green)
                }
            }
            .font(.subheadline)
            Slider(value: $value, in: range, step: step)
                .frame(minHeight: 44)
                .accessibilityLabel(title)
                .accessibilityValue(formatted)
                .accessibilityIdentifier(identifier.isEmpty ? "slider.\(title)" : identifier)
        }
        .padding(.vertical, compact ? 0 : 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("row." + (identifier.isEmpty ? "slider.\(title)" : identifier))
    }
}

struct PhoneIntegerSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit = ""
    var body: some View {
        PhoneSlider(title: title, value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                    range: Double(range.lowerBound)...Double(range.upperBound), step: 1, unit: unit)
    }
}

struct PhoneReadout: View {
    let title: String
    let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            LabeledContent(title, value: value)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.secondary)
                Text(value)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
