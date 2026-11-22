import SwiftUI
import EarStudioCore
import EarStudioSession
import EarStudioUI

struct PhoneSettingsView: View {
    @EnvironmentObject private var model: IOSStudioModel
    var body: some View {
        List {
            SessionMessageSection()
            if !model.session.canEdit {
                Section {
                    Text("Connect to EarStudio to edit settings. Unsupported firmware options stay unavailable.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Device settings") {
                NavigationLink { PhoneSoundSettings() } label: { Label("Output & sound", systemImage: "headphones") }
                    .frame(minHeight: 44).accessibilityIdentifier("settings.sound")
                NavigationLink { PhoneInputSettings() } label: { Label("Inputs & codecs", systemImage: "waveform") }
                    .frame(minHeight: 44).accessibilityIdentifier("settings.inputs")
                NavigationLink { PhoneAmbientSettings() } label: { Label("Ambient & calls", systemImage: "mic") }
                    .frame(minHeight: 44).accessibilityIdentifier("settings.ambient")
                NavigationLink { PhonePowerSettings() } label: { Label("Power & device", systemImage: "battery.75percent") }
                    .frame(minHeight: 44).accessibilityIdentifier("settings.power")
            }
            Section {
                NavigationLink { PhoneDiagnosticsView() } label: { Label("Diagnostics & about", systemImage: "info.circle") }
                    .frame(minHeight: 44).accessibilityIdentifier("settings.diagnostics")
            }
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("screen.settings")
    }
}

private struct PhoneSoundSettings: View {
    @EnvironmentObject private var model: IOSStudioModel
    private var s: DeviceSession { model.session }
    var body: some View {
        List {
            SessionMessageSection()
            Section {
                Picker("Output mode", selection: Binding(get: { s.state.outputMode }, set: { s.setOutput($0) })) {
                    Text("3.5 mm · 1× current").tag(0)
                    Text("3.5 mm · 2× current").tag(1)
                    Text("2.5 mm · 1× voltage").tag(2)
                    Text("2.5 mm · 2× voltage").tag(3)
                }.pickerStyle(.navigationLink)
                    .disabled(!s.available(.audio, .outputMode) || s.state.outputLocked)
                Toggle("Lock output selection", isOn: s.boolBinding(\.outputLocked, .outputLock))
                    .disabled(!s.available(.audio, .outputLock))
            } header: { Text("Analog output") } footer: {
                Text("The mode describes the amplifier, not headphone presence. With no 3.5 mm plug inserted, ES100 may report balanced mode even when both sockets are empty.")
            }
            Section {
                Picker("DAC filter", selection: s.intBinding(\.dacFilter, .dacFilter, range: 0...3)) {
                    Text("Sharp roll-off").tag(0); Text("Slow roll-off").tag(1)
                    Text("Short delay · sharp").tag(2); Text("Short delay · slow").tag(3)
                }.pickerStyle(.navigationLink).disabled(!s.available(.audio, .dacFilter))
                Picker("Oversampling", selection: s.intBinding(\.oversampling, .oversampling, range: 0...2)) {
                    Text("1×").tag(0); Text("2×").tag(1); Text("4×").tag(2)
                }.disabled(!s.available(.audio, .oversampling))
                PhoneIntegerSlider(title: "Crossfeed", value: s.intBinding(\.crossfeed, .crossfeed, range: 0...10), range: 0...10)
                    .disabled(!s.available(.device, .crossfeed))
                PhoneIntegerSlider(title: "DCT level", value: s.intBinding(\.dct, .dct, range: 0...10), range: 0...10)
                    .disabled(!s.available(.audio, .dct))
            } header: { Text("DAC processing") } footer: {
                Text("Crossfeed blends a little of each channel into the other. Set crossfeed or DCT to zero to turn that processing off.")
            }
            Section("Channel trim") {
                PhoneSlider(title: "Left", value: Binding(get: { s.state.leftTrim }, set: { s.setTrim(left: $0, right: s.state.rightTrim) }), range: -6...0, step: 0.05)
                PhoneSlider(title: "Right", value: Binding(get: { s.state.rightTrim }, set: { s.setTrim(left: s.state.leftTrim, right: $0) }), range: -6...0, step: 0.05)
            }.disabled(!s.available(.info, .trim))
        }.navigationTitle("Output & sound").navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhoneInputSettings: View {
    @EnvironmentObject private var model: IOSStudioModel
    private var s: DeviceSession { model.session }
    var body: some View {
        List {
            SessionMessageSection()
            Section {
                codec("AAC", path: \.aac)
                codec("aptX", path: \.aptx)
                codec("aptX HD", path: \.aptxHD)
            } header: { Text("Allowed Bluetooth codecs") } footer: {
                Text("These settings affect ES100 connections with any audio source. Enabling a codec does not add support to your iPhone. SBC stays enabled. Changes apply on the next audio connection.")
            }
            Section {
                PhoneIntegerSlider(title: "Bluetooth buffer", value: s.intBinding(\.buffer, .buffer, range: 1...10), range: 1...10)
                    .disabled(!s.available(.info, .buffer) || s.state.codec == 4)
            } footer: {
                Text("Pause playback before changing the buffer. The original app recommends 7 or above. LDAC uses a fixed buffer.")
            }
            Section {
                Picker("USB format", selection: s.intBinding(\.usbBits, .usbBits, range: 0...(s.state.supportsQ ? 2 : 1))) {
                    Text("48 kHz · 16-bit").tag(0)
                    Text("48 kHz · 24-bit (Mac)").tag(1)
                    if s.state.supportsQ { Text("44.1 / 48 kHz · 16-bit").tag(2) }
                }.pickerStyle(.navigationLink).disabled(!s.available(.info, .usbBits))
            } header: { Text("USB DAC") } footer: {
                Text("Restart ES100 after changing USB format. The 24-bit option is intended for a direct USB connection to a Mac.")
            }
            Section("Jitter processing") {
                Toggle("Bluetooth", isOn: Binding(get: { s.state.jitterBluetooth }, set: { s.setJitter(usb: s.state.jitterUSB, bluetooth: $0) }))
                Toggle("USB", isOn: Binding(get: { s.state.jitterUSB }, set: { s.setJitter(usb: $0, bluetooth: s.state.jitterBluetooth) }))
            }.disabled(!s.available(.audio, .jitter))
        }.navigationTitle("Inputs & codecs").navigationBarTitleDisplayMode(.inline)
    }
    private func codec(_ title: String, path: KeyPath<DeviceState, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { s.state[keyPath: path] }, set: { value in
            s.setCodecs(aac: path == \DeviceState.aac ? value : s.state.aac,
                        aptx: path == \DeviceState.aptx ? value : s.state.aptx,
                        hd: path == \DeviceState.aptxHD ? value : s.state.aptxHD)
        })).disabled(!s.available(.device, .codecs))
    }
}

private struct PhoneAmbientSettings: View {
    @EnvironmentObject private var model: IOSStudioModel
    private var s: DeviceSession { model.session }
    var body: some View {
        List {
            SessionMessageSection()
            Section {
                Toggle("Ambient mode", isOn: s.boolBinding(\.ambient, .ambient)).disabled(!s.available(.audio, .ambient))
                PhoneIntegerSlider(title: "Ambient mix", value: s.intBinding(\.ambientRatio, .ambientRatio, range: 0...100), range: 0...100, unit: "%")
                    .disabled(!s.available(.audio, .ambientRatio))
                Toggle("Device button shortcut", isOn: s.boolBinding(\.ambientShortcut, .ambientShortcut))
                    .disabled(!s.available(.audio, .ambientShortcut))
            } header: { Text("Ambient sound") } footer: {
                Text("Mix 0% is music only; 100% is ambient only. The shortcut uses a two-second hold of the Next track button.")
            }
            Section("Ambient microphone") { PhoneMicrophoneControls(ambient: true) }
            Section {
                Toggle("Mute call audio", isOn: s.boolBinding(\.callMuted, .callMute)).disabled(!s.available(.audio, .callMute))
                PhoneMicrophoneControls(ambient: false)
                PhoneSlider(title: "Microphone loopback", value: s.doubleBinding(\.loopback, .loopback, range: -60...0), range: -60...0)
                    .disabled(!s.available(.device, .loopback))
                Picker("Hands-free profile", selection: s.intBinding(\.hfp, .hfp, range: 0...1)) {
                    Text("HFP 1.7").tag(0); Text("HFP 1.5 (compatibility)").tag(1)
                }.pickerStyle(.navigationLink).disabled(!s.available(.info, .hfp))
            } header: { Text("Voice calls") } footer: { Text("Loopback lets you hear your microphone during calls. Restart ES100 after changing the hands-free profile.") }
        }.navigationTitle("Ambient & calls").navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhoneMicrophoneControls: View {
    @EnvironmentObject private var model: IOSStudioModel
    let ambient: Bool
    private var s: DeviceSession { model.session }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Microphone gain").font(.subheadline)
            Text("\(s.state.microphoneDecibels(ambient: ambient).formatted()) dB")
                .font(.subheadline.monospacedDigit()).foregroundStyle(StudioTheme.green)
            Slider(value: Binding(get: { Double(ambient ? s.state.ambientGain : s.state.micGain) }, set: {
                s.setMic(ambient: ambient, preamp: ambient ? s.state.ambientPreamp : s.state.micPreamp, gain: Int($0.rounded()))
            }), in: 0...22, step: 1)
            .frame(minHeight: 44)
            .accessibilityLabel(ambient ? "Ambient microphone gain" : "Call microphone gain")
            .accessibilityValue("\(s.state.microphoneDecibels(ambient: ambient).formatted()) decibels")
        }.disabled(!s.available(.audio, ambient ? .ambientMic : .mic))
        Toggle("Microphone preamp (+21 dB)", isOn: Binding(get: { ambient ? s.state.ambientPreamp : s.state.micPreamp }, set: {
            s.setMic(ambient: ambient, preamp: $0, gain: ambient ? s.state.ambientGain : s.state.micGain)
        })).disabled(!s.available(.audio, ambient ? .ambientMic : .mic))
    }
}

private struct PhonePowerSettings: View {
    @EnvironmentObject private var model: IOSStudioModel
    private var s: DeviceSession { model.session }
    var body: some View {
        List {
            SessionMessageSection()
            Section {
                PhoneReadout(title: "Battery", value: s.state.loaded.contains(.battery) ? "\(s.state.battery)%" : "—")
                PhoneReadout(title: "Voltage", value: s.state.millivolts > 0 ? String(format: "%.2f V", Double(s.state.millivolts) / 1000) : "—")
                PhoneReadout(title: "Charging", value: s.canEdit ? (s.state.charging ? "Charging" : "Not charging") : "—")
                Toggle("Battery care", isOn: s.boolBinding(\.batteryCare, .batteryCare)).disabled(!s.available(.info, .batteryCare))
                Toggle("USB charging", isOn: s.boolBinding(\.chargerEnabled, .charger)).disabled(!s.available(.audio, .charger))
                Picker("Auto power", selection: s.intBinding(\.autoPower, .autoPower, range: 0...2)) {
                    Text("Normal").tag(0)
                    Text("Off when charger connects").tag(1)
                    Text("Off when USB power disconnects").tag(2)
                }.pickerStyle(.navigationLink).disabled(!s.available(.device, .autoPower))
            } header: { Text("Power & battery") } footer: {
                Text("Battery care limits charging to approximately 80–90%; restart ES100 after changing it. Disabling USB charging uses battery power while connected by USB.")
            }
            Section("Device controls") {
                Toggle("Reconnect second device", isOn: s.boolBinding(\.reconnect, .reconnect)).disabled(!s.available(.info, .reconnect))
                Picker("Status light", selection: s.intBinding(\.led, .led, range: 0...2)) {
                    Text("Color").tag(0); Text("White").tag(1); Text("Off").tag(2)
                }.disabled(!s.available(.info, .led))
                PhoneSlider(title: "Maximum analog volume", value: s.doubleBinding(\.volumeLimit, .volumeLimit, range: -60...6), range: -60...6)
                    .disabled(!s.available(.info, .volumeLimit))
                PhoneSlider(title: "Notification volume", value: s.doubleBinding(\.toneVolume, .toneVolume, range: -60...0), range: -60...0)
                    .disabled(!s.available(.device, .toneVolume))
            }
        }.navigationTitle("Power & device").navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhoneDiagnosticsView: View {
    @EnvironmentObject private var model: IOSStudioModel
    @State private var confirmingForget = false
    private var s: DeviceSession { model.session }
    private var diagnostics: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return "ES100 Control for iOS \(version)\nFirmware: \(s.state.firmware ?? "unknown")\n" +
            s.logs.map { "\($0.date.ISO8601Format()) \($0.text)" }.joined(separator: "\n")
    }
    var body: some View {
        List {
            SessionMessageSection()
            Section {
                Text("An independent companion for EarStudio ES100 and ES100 MK2.")
                Text("Firmware flashing and factory reset are not included. Audio settings live on the device; your preset library is stored on this iPhone.")
                    .font(.callout).foregroundStyle(.secondary)
                PhoneReadout(title: "Firmware", value: s.state.firmware ?? "—")
                Button("Refresh device settings") { s.refresh() }
                    .frame(minHeight: 44).disabled(s.phase != .connected)
                Button("Forget device confirmation", role: .destructive) { confirmingForget = true }
                    .frame(minHeight: 44).disabled(s.address.isEmpty)
            }
            Section {
                ShareLink(item: diagnostics) { Label("Share diagnostics", systemImage: "square.and.arrow.up") }
                    .frame(minHeight: 44).accessibilityIdentifier("diagnostics.share")
                NavigationLink {
                    PhoneConnectionLogView(diagnostics: diagnostics)
                } label: {
                    Label("View connection log", systemImage: "list.bullet.rectangle")
                }
                .frame(minHeight: 44).accessibilityIdentifier("diagnostics.viewLog")
            } header: { Text("Diagnostics") } footer: {
                Text("Recent connection activity is kept in memory (up to 300 entries). Device authorization keys are excluded.")
            }
            Section {
                NavigationLink("Privacy policy") {
                    ScrollView {
                        Text("ES100 Control does not collect data or send analytics to the developer. Bluetooth is used to discover and control your EarStudio. Presets and preferences remain on your iPhone; device authorization is stored in the iOS Keychain. Diagnostics leave the app only when you choose Share diagnostics. Files you export and links you open are handled by the destination app or service, under its privacy policy. Device backups may include app data according to your Apple settings. For privacy questions, contact the maintainer through the project’s GitHub page.")
                            .padding()
                    }
                    .navigationTitle("Privacy policy")
                }
                AboutFooter()
            }
        }
        .navigationTitle("Diagnostics & about").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Forget this device’s authorization?", isPresented: $confirmingForget, titleVisibility: .visible) {
            Button("Forget confirmation", role: .destructive) { s.forgetKey() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You will need to authorize the app again on your next connection.") }
    }
}

private struct PhoneConnectionLogView: View {
    let diagnostics: String
    @EnvironmentObject private var model: IOSStudioModel

    var body: some View {
        List {
            Section {
                if model.session.logs.isEmpty {
                    Text("No connection activity yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.session.logs.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.date, style: .time)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.text).font(.caption.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Newest first")
            } footer: {
                Text("Shows up to 300 recent entries. Device authorization keys are excluded.")
            }
        }
        .navigationTitle("Connection log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: diagnostics) {
                Label("Share diagnostics", systemImage: "square.and.arrow.up")
            }
        }
    }
}
