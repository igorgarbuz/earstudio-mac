import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        VStack(spacing: 18) {
            Panel(title: "") {
                HStack(spacing: 30) {
                    DeviceImage()
                    VStack(alignment: .leading, spacing: 18) {
                        Text("ES100 / ES100 MK2").sectionCaption()
                        Text(model.deviceName).font(.system(size: 33, weight: .light)).tracking(-0.8)
                        Text("Bluetooth and USB DAC / headphone amplifier.").font(.system(size: 13)).foregroundStyle(StudioTheme.secondary)
                        StatusPill(text: model.isDemo ? "DEMO MODE" : model.phase.rawValue.uppercased(), color: model.phase.statusColor)
                        HStack(spacing: 12) {
                            if model.phase == .connected { Button("Refresh settings") { model.refresh() }; Button("Disconnect") { model.disconnect() } }
                            else { Button("Connect") { model.requestConnection() }.buttonStyle(.borderedProminent).disabled(model.isBusy) }
                        }.padding(.top, 5)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Panel(title: "Signal path") {
                HStack(spacing: 12) {
                    Metric(label: "Source", value: model.canEdit ? model.state.inputName : "—")
                    Image(systemName: "chevron.right").foregroundStyle(StudioTheme.secondary).font(.caption)
                    Metric(label: "Format", value: model.canEdit ? "\(model.state.rateName) / \(model.state.bitsName)" : "—")
                    Image(systemName: "chevron.right").foregroundStyle(StudioTheme.secondary).font(.caption)
                    Metric(label: "Processing", value: model.canEdit ? (model.state.eqEnabled ? "10-band EQ" : "EQ bypassed") : "—")
                    Image(systemName: "chevron.right").foregroundStyle(StudioTheme.secondary).font(.caption)
                    Metric(label: "Output mode", value: model.canEdit ? (model.state.outputMode < 2 ? "3.5 mm" : "2.5 mm balanced") : "—")
                }
            }
            HStack(spacing: 18) {
                Panel(title: "On the device", subtitle: "Active EQ and audio settings live on your ES100. After configuring it, you can close this app and keep listening from Bluetooth or USB.") {
                    Label("Hardware audio processing", systemImage: "cpu").font(.system(size: 12)).foregroundStyle(StudioTheme.green)
                }
                Panel(title: "In your library", subtitle: "EQ presets are stored on this Mac. Import Android preferences XML or exchange presets as JSON.") {
                    Label("\(model.presets.count) saved presets", systemImage: "square.stack").font(.system(size: 12)).foregroundStyle(StudioTheme.green)
                }
            }
        }
    }
}

struct SoundView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        VStack(spacing: 18) {
            Panel(title: "Analog output", subtitle: "Selected output and amplifier mode; this does not confirm that headphones are plugged in.") {
                InfoButton(topic: .output)
                HStack(spacing: 10) {
                    ForEach(0..<4) { mode in
                        Button { model.setOutput(mode) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack { Image(systemName: mode < 2 ? "headphones" : "waveform.path"); Spacer(); if model.state.outputMode == mode { Image(systemName: "checkmark.circle.fill") } }
                                    .foregroundStyle(model.state.outputMode == mode ? StudioTheme.green : StudioTheme.secondary)
                                Text(mode < 2 ? "3.5 mm" : "2.5 mm").font(.system(size: 19, weight: .medium, design: .rounded))
                                Text(["1× current", "2× current", "1× voltage", "2× voltage"][mode]).font(.system(size: 10)).foregroundStyle(StudioTheme.secondary)
                            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                                .background(model.state.outputMode == mode ? StudioTheme.green.opacity(0.065) : .black.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.state.outputMode == mode ? StudioTheme.green.opacity(0.4) : StudioTheme.border))
                        }.buttonStyle(.plain).disabled(!model.available(.audio, .outputMode) || model.state.outputLocked)
                    }
                }
                SettingToggle(title: "Lock output selection", detail: "Keep the selected connection and amplifier mode.", value: model.boolBinding(\.outputLocked, .outputLock)).disabled(!model.available(.audio, .outputLock))
                Text("With the 3.5 mm jack empty, ES100 can report 2.5 mm balanced mode even when no headphones are connected.")
                    .font(.caption).foregroundStyle(StudioTheme.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                Panel(title: "DAC filter", subtitle: "AK4375A reconstruction filter") {
                    InfoButton(topic: .dac)
                    Picker("DAC filter", selection: model.intBinding(\.dacFilter, .dacFilter, range: 0...3)) {
                        Text("Sharp roll-off").tag(0); Text("Slow roll-off").tag(1)
                        Text("Short delay · sharp").tag(2); Text("Short delay · slow").tag(3)
                    }.labelsHidden().frame(maxWidth: .infinity).disabled(!model.available(.audio, .dacFilter))
                }
                Panel(title: "Oversampling", subtitle: "Digital processing rate") {
                    Picker("Oversampling", selection: model.intBinding(\.oversampling, .oversampling, range: 0...2)) {
                        Text("1×").tag(0); Text("2×").tag(1); Text("4×").tag(2)
                    }.pickerStyle(.segmented).labelsHidden().disabled(!model.available(.audio, .oversampling))
                }
            }
            Panel(title: "Sound processing") {
                InfoButton(topic: .processing)
                IntegerSlider(title: "Crossfeed", value: model.intBinding(\.crossfeed, .crossfeed, range: 0...10), range: 0...10).disabled(!model.available(.device, .crossfeed))
                Text("Blend a little of each channel into the other. 0 turns crossfeed off.").font(.caption).foregroundStyle(StudioTheme.secondary)
                Divider().overlay(StudioTheme.border)
                IntegerSlider(title: "DCT level", value: model.intBinding(\.dct, .dct, range: 0...10), range: 0...10).disabled(!model.available(.audio, .dct))
                Text("Optional DCT processing in the ES100 firmware. 0 turns it off.").font(.caption).foregroundStyle(StudioTheme.secondary)
            }
            Panel(title: "Channel trim") {
                HStack(spacing: 35) {
                    ValueSlider(title: "Left", value: Binding(get: { model.state.leftTrim }, set: { model.setTrim(left: $0, right: model.state.rightTrim) }), range: -6...0, step: 0.05)
                    ValueSlider(title: "Right", value: Binding(get: { model.state.rightTrim }, set: { model.setTrim(left: model.state.leftTrim, right: $0) }), range: -6...0, step: 0.05)
                }.disabled(!model.available(.info, .trim))
            }
        }
    }
}

struct InputView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        VStack(spacing: 18) {
            Panel(title: "Incoming audio") {
                HStack {
                    Metric(label: "Input", value: model.canEdit ? model.state.inputName : "—")
                    Metric(label: "Codec", value: model.canEdit && model.state.input > 1 ? model.state.codecName : "—")
                    Metric(label: "Sample rate", value: model.canEdit ? model.state.rateName : "—")
                    Metric(label: "Resolution", value: model.canEdit ? model.state.bitsName : "—")
                }
            }
            Panel(title: "Bluetooth codecs", subtitle: "Allow the source device to negotiate these codecs. Changes apply on the next audio connection.") {
                InfoButton(topic: .input)
                HStack(spacing: 30) {
                    codecToggle("AAC", path: \.aac)
                    codecToggle("aptX", path: \.aptx)
                    codecToggle("aptX HD", path: \.aptxHD)
                }.disabled(!model.available(.device, .codecs))
                Text("SBC remains enabled. Configure LDAC on your audio source device.").font(.caption).foregroundStyle(StudioTheme.secondary)
                Divider()
                IntegerSlider(title: "Bluetooth buffer", value: model.intBinding(\.buffer, .buffer, range: 1...10), range: 1...10)
                    .disabled(!model.available(.info, .buffer) || model.state.codec == 4)
                Text("Pause Bluetooth playback before changing the buffer. The original app recommends 7 or above. LDAC uses a fixed buffer.").font(.caption).foregroundStyle(StudioTheme.secondary)
            }
            Panel(title: "USB DAC", subtitle: "Changes take effect after restarting the ES100.") {
                Picker("USB format", selection: model.intBinding(\.usbBits, .usbBits, range: 0...(model.state.supportsQ ? 2 : 1))) {
                    Text("48 kHz · 16-bit").tag(0)
                    Text("48 kHz · 24-bit (Mac)").tag(1)
                    if model.state.supportsQ { Text("44.1 / 48 kHz · 16-bit").tag(2) }
                }.disabled(!model.available(.info, .usbBits))
                Text("The ES100’s 24-bit mode requires a direct USB connection to a Mac, without a USB hub.").font(.caption).foregroundStyle(StudioTheme.secondary)
            }
            Panel(title: "Jitter processing") {
                SettingToggle(title: "Bluetooth", value: Binding(get: { model.state.jitterBluetooth }, set: { model.setJitter(usb: model.state.jitterUSB, bluetooth: $0) }))
                Divider()
                SettingToggle(title: "USB", value: Binding(get: { model.state.jitterUSB }, set: { model.setJitter(usb: $0, bluetooth: model.state.jitterBluetooth) }))
            }.disabled(!model.available(.audio, .jitter))
        }
    }
    private func codecToggle(_ name: String, path: KeyPath<DeviceState, Bool>) -> some View {
        SettingToggle(title: name, value: Binding(get: { model.state[keyPath: path] }, set: { value in
            model.setCodecs(aac: path == \DeviceState.aac ? value : model.state.aac,
                            aptx: path == \DeviceState.aptx ? value : model.state.aptx,
                            hd: path == \DeviceState.aptxHD ? value : model.state.aptxHD)
        }))
    }
}

struct AmbientView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        VStack(spacing: 18) {
            Panel(title: "Ambient mode", subtitle: "Bring sound from the ES100 microphone into your headphones.") {
                SettingToggle(title: "Enable ambient mode", value: model.boolBinding(\.ambient, .ambient)).disabled(!model.available(.audio, .ambient))
                Divider()
                IntegerSlider(title: "Ambient mix", value: model.intBinding(\.ambientRatio, .ambientRatio, range: 0...100), range: 0...100, step: 5, unit: "%").disabled(!model.available(.audio, .ambientRatio))
                HStack { Text("Music only"); Spacer(); Text("Ambient only") }.font(.caption).foregroundStyle(StudioTheme.secondary)
                SettingToggle(title: "Device button shortcut", detail: "Hold the Next track button for two seconds to toggle ambient mode.", value: model.boolBinding(\.ambientShortcut, .ambientShortcut)).disabled(!model.available(.audio, .ambientShortcut))
            }
            Panel(title: "Ambient microphone") {
                microphoneControls(ambient: true)
            }.disabled(!model.available(.audio, .ambientMic))
            Panel(title: "Voice calls") {
                SettingToggle(title: "Mute call audio", value: model.boolBinding(\.callMuted, .callMute)).disabled(!model.available(.audio, .callMute))
                Divider()
                microphoneControls(ambient: false)
                Divider()
                ValueSlider(title: "Microphone loopback", value: model.doubleBinding(\.loopback, .loopback, range: -60...0), range: -60...0).disabled(!model.available(.device, .loopback))
                Text("Hear your own microphone during a call.").font(.caption).foregroundStyle(StudioTheme.secondary)
                Picker("Hands-free profile", selection: model.intBinding(\.hfp, .hfp, range: 0...1)) {
                    Text("HFP 1.7").tag(0); Text("HFP 1.5 (compatibility)").tag(1)
                }.disabled(!model.available(.info, .hfp))
                Text("Restart ES100 after changing the hands-free profile.").font(.caption).foregroundStyle(StudioTheme.secondary)
            }
        }
    }
    private func microphoneControls(ambient: Bool) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 9) {
                HStack {
                    Text("Microphone gain").font(.system(size: 13, weight: .medium)); Spacer()
                    Text(String(format: "%.1f dB", model.state.microphoneDecibels(ambient: ambient))).font(.system(size: 12, design: .monospaced)).foregroundStyle(StudioTheme.green)
                }
                Slider(value: Binding(get: { Double(ambient ? model.state.ambientGain : model.state.micGain) }, set: {
                    model.setMic(ambient: ambient, preamp: ambient ? model.state.ambientPreamp : model.state.micPreamp, gain: Int($0.rounded()))
                }), in: 0...22).controlSize(.small).accessibilityLabel("Microphone gain")
                    .accessibilityValue(String(format: "%.1f decibels", model.state.microphoneDecibels(ambient: ambient)))
            }
            SettingToggle(title: "+21 dB microphone preamp", value: Binding(get: { ambient ? model.state.ambientPreamp : model.state.micPreamp }, set: {
                model.setMic(ambient: ambient, preamp: $0, gain: ambient ? model.state.ambientGain : model.state.micGain)
            }))
        }.disabled(!model.available(.audio, ambient ? .ambientMic : .mic))
    }
}

struct SystemView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        VStack(spacing: 18) {
            Panel(title: "Power & battery") {
                HStack {
                    Metric(label: "Battery", value: model.state.loaded.contains(.battery) ? "\(model.state.battery)%" : "—")
                    Metric(label: "Voltage", value: model.state.millivolts > 0 ? String(format: "%.2f V", Double(model.state.millivolts) / 1000) : "—")
                    Metric(label: "Charging", value: model.canEdit ? (model.state.charging ? "Charging" : "Not charging") : "—")
                }
                Divider()
                SettingToggle(title: "Battery care", detail: "Limit charging to approximately 80–90%. Restart the ES100 after changing this setting.", value: model.boolBinding(\.batteryCare, .batteryCare)).disabled(!model.available(.info, .batteryCare))
                SettingToggle(title: "USB charging", detail: "Turn off to run from the battery while connected by USB.", value: model.boolBinding(\.chargerEnabled, .charger)).disabled(!model.available(.audio, .charger))
                Picker("Auto power", selection: model.intBinding(\.autoPower, .autoPower, range: 0...2)) {
                    Text("Normal").tag(0); Text("Off when charger connects").tag(1); Text("Off when USB power disconnects").tag(2)
                }.disabled(!model.available(.device, .autoPower))
            }
            Panel(title: "Device controls") {
                SettingToggle(title: "Reconnect second device", detail: "Restore the second Bluetooth connection automatically.", value: model.boolBinding(\.reconnect, .reconnect)).disabled(!model.available(.info, .reconnect))
                Picker("Status light", selection: model.intBinding(\.led, .led, range: 0...2)) {
                    Text("Color").tag(0); Text("White").tag(1); Text("Off").tag(2)
                }.disabled(!model.available(.info, .led))
                Divider()
                ValueSlider(title: "Maximum analog volume", value: model.doubleBinding(\.volumeLimit, .volumeLimit, range: -60...6), range: -60...6).disabled(!model.available(.info, .volumeLimit))
                ValueSlider(title: "Notification volume", value: model.doubleBinding(\.toneVolume, .toneVolume, range: -60...0), range: -60...0).disabled(!model.available(.device, .toneVolume))
            }
            Panel(title: "About this device") {
                HStack {
                    Metric(label: "Firmware", value: model.state.firmware ?? "—")
                    Metric(label: "Control link", value: model.isDemo ? "Simulated" : (model.canEdit ? "Bluetooth serial" : "Disconnected"))
                    Metric(label: "Companion", value: AppMetadata.version)
                }
                HStack {
                    Button("Refresh settings") { model.refresh() }.disabled(!model.canEdit || model.isDemo)
                    Button("Diagnostics…") { model.showDiagnostics = true }
                    Spacer()
                    Button("Forget device confirmation") { model.forgetKey() }.disabled(model.address.isEmpty)
                }
                Text("An independent companion for ES100 and ES100 MK2. Firmware updates and factory reset are not implemented.").font(.caption).foregroundStyle(StudioTheme.secondary)
            }
        }
    }
}

// Independently worded help, based on the recovered Android 1.9.0 resources.
// Resource IDs and the product image's origin are recorded in Docs/Provenance.md.
enum InfoTopic: String, CaseIterable, Identifiable {
    case output = "Balanced and unbalanced output"
    case volume = "Analog and source volume"
    case equalizer = "EQ, preamp, and headroom"
    case dac = "DAC filters and oversampling"
    case processing = "Crossfeed and DCT"
    case input = "Bluetooth, USB, and jitter"
    case ambient = "Ambient sound and calls"
    case power = "Battery and stored settings"
    var id: String { rawValue }
}

struct InfoButton: View {
    let topic: InfoTopic
    var compact = false
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            if compact { Image(systemName: "info.circle") }
            else { Label("About this setting", systemImage: "info.circle") }
        }
            .help(topic.rawValue)
            .buttonStyle(.plain).font(.caption).foregroundStyle(StudioTheme.green)
            .accessibilityLabel("About \(topic.rawValue)")
            .sheet(isPresented: $showing) { InfoSheet(topic: topic) }
    }
}

struct InfoSheet: View {
    let topic: InfoTopic
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(topic.rawValue).font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView { InfoContent(topic: topic).padding(.trailing, 8) }
                .frame(maxHeight: 520)
        }.padding(28).frame(width: 650).background(StudioTheme.background)
    }
}

struct InfoView: View {
    var body: some View {
        VStack(spacing: 18) {
            ForEach(InfoTopic.allCases) { topic in
                Panel(title: topic.rawValue) { InfoContent(topic: topic) }
            }
        }.textSelection(.enabled)
    }
}

struct InfoContent: View {
    let topic: InfoTopic
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch topic {
            case .output:
                paragraph("The 3.5 mm single-ended output carries left and right signals with a shared ground: L, R, and GND. The 2.5 mm balanced output uses four separate connections: L+, L−, R+, and R−. Each headphone driver connects between its channel’s + and − outputs.")
                paragraph("The ES100 uses two DAC/amplifier chips, one per channel. Balanced wiring removes the shared headphone ground connection. The connector alone does not establish sound quality; the amplifier circuit, headphone load, and listening level also matter.")
                HStack(alignment: .top, spacing: 20) {
                    modes(title: "3.5 mm · Unbalanced", lines: ["1× current: normal mode; approximately 1 Ω output impedance.", "2× current: parallel amplifier mode; approximately 0.5 Ω output impedance."])
                    modes(title: "2.5 mm · Balanced", lines: ["1× voltage: normal voltage limit.", "2× voltage: higher voltage limit for high-impedance headphones."])
                }
                paragraph("2× current does not double the voltage. The original app describes 1× and 2× balanced voltage modes as differing in their voltage limit. Choose the mode for the connected headphones, then use output lock to keep it selected.")
                caution("Use the 2.5 mm output only with a compatible balanced cable. Do not adapt it to 3.5 mm single-ended, AUX, or RCA: joining the negative outputs can damage the amplifier. The ES100 pin order from tip to sleeve is R−, R+, L+, L−. Check the cable wiring before connecting.")
                caution("The original app reserves 2.5 mm / 2× voltage for headphones above 300 Ω and warns against low-impedance earphones. Lower analog volume before changing headphones or amplifier mode.")
                paragraph("The original app allows balanced output when the 3.5 mm jack is empty; inserting a 3.5 mm plug selects the single-ended connection.")
                paragraph("The output label reports the selected amplifier mode, not headphone presence. An empty device can therefore show 2.5 mm balanced; that does not mean a balanced cable is connected.")
            case .volume:
                paragraph("Analog volume controls the ES100’s programmable gain amplifier (PGA). Source volume changes the signal level sent by the phone or computer. These are separate controls; the companion’s bottom slider adjusts analog volume in dB, not the Mac’s system volume.")
                paragraph("The mode below the slider is the ES100’s selected output, not a headphone detector. It can show 2.5 mm balanced with no headphones plugged in; inserting a 3.5 mm plug selects unbalanced output.")
                paragraph("The Android app recommends a high source level and using analog volume for listening adjustments. Before raising the source level, lower analog volume, then increase it gradually to a comfortable level. This companion does not automatically change source volume on connection.")
                paragraph("Maximum analog volume caps the device’s analog gain. Notification volume adjusts the ES100’s local tones relative to analog volume; it is separate from music volume.")
            case .equalizer:
                paragraph("The ES100 has ten fixed EQ center frequencies. Each band changes gain; Q sets how wide the adjustment is. Wide uses Q 0.7071, narrow uses Q 1.4142. This is a graphic EQ, rather than a parametric EQ with freely movable frequencies.")
                paragraph("Boosting bands can push the digital signal beyond its available range and cause clipping. A lower preamp setting and −6 or −12 dB digital headroom leave space for those boosts. Several overlapping boosts may need more headroom than one band alone.")
                paragraph("The optional +6 dB analog compensation raises gain after digital processing. It can offset part of the level reduction but cannot repair digital clipping. The response graph is an estimate and excludes this headroom and compensation.")
            case .dac:
                paragraph("The AK4375A DAC offers sharp and slow roll-off filters, with short-delay variants. These change the reconstruction filter’s frequency and time response. They do not change EQ band gains or the source codec.")
                paragraph("Oversampling offers 1×, 2×, and 4× processing rates. It does not add detail missing from the source recording. The original app notes that a higher setting is not guaranteed to improve performance; compare settings at the same listening level.")
            case .processing:
                paragraph("Crossfeed mixes some of each channel into the other to approximate aspects of loudspeaker listening through headphones. It changes stereo separation. Level 0 disables it.")
                paragraph("DCT (Distinctive Clear Technology) is optional Radsone processing implemented in the ES100 firmware. This open-source companion selects its level; it does not implement the DCT algorithm. Level 0 disables it. The original app’s claims about restored detail are not independently verified here.")
            case .input:
                paragraph("Bluetooth codec selection is negotiated with the source. Enabling AAC, aptX, or aptX HD permits negotiation; it does not force that codec. SBC stays available. LDAC is configured on the source. The Input page reports the format received by the ES100.")
                paragraph("The Bluetooth buffer trades latency against tolerance of interruptions. Pause playback before changing it. The original app recommends level 7 or higher; LDAC uses a fixed buffer.")
                paragraph("USB format changes require an ES100 restart. The original app specifies a direct Mac USB connection for 24-bit mode. Jitter processing is separately selectable for Bluetooth and USB; if periodic clicks occur, the original help suggests disabling it for that input.")
            case .ambient:
                paragraph("Ambient mode mixes the built-in microphone with streamed audio. The mix setting changes the music/microphone balance; microphone gain changes the captured level before the mix. Higher gain also raises background noise.")
                paragraph("Call microphone loopback feeds the microphone into the headphone output so you can hear yourself. If using speakers, this can create acoustic feedback. Ambient and call microphone settings are separate.")
            case .power:
                paragraph("Battery care limits charging to approximately 80–90%, depending on conditions. The original app says this setting requires a restart. With USB charging disabled, the ES100 operates from its battery while connected to USB.")
                paragraph("Active EQ and device settings are stored on the ES100 and apply to Bluetooth and USB audio after the app is closed. Named companion presets are a separate library stored on this Mac. Connecting reads the device’s current settings.")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
    private func paragraph(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(StudioTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func caution(_ text: String) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle") }
            .font(.system(size: 12)).foregroundStyle(.orange)
    }
    private func modes(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold))
            ForEach(lines, id: \.self) { paragraph($0) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
