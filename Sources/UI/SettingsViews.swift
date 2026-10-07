import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        VStack(spacing: 18) {
            Panel(title: "") {
                HStack(spacing: 30) {
                    DeviceIllustration()
                    VStack(alignment: .leading, spacing: 18) {
                        Text("SMALL DEVICE. BIG SOUND.").sectionCaption()
                        Text(model.deviceName).font(.system(size: 33, weight: .light)).tracking(-0.8)
                        Text("A native home for your portable studio.").font(.system(size: 13)).foregroundStyle(StudioTheme.secondary)
                        StatusPill(text: model.isDemo ? "EXPLORING DEMO" : model.phase.rawValue.uppercased(), color: model.isDemo ? .orange : StudioTheme.green)
                        HStack(spacing: 12) {
                            if model.phase == .connected { Button("Refresh settings") { model.refresh() }; Button("Disconnect") { model.disconnect() } }
                            else { Button("Connect EarStudio…") { model.prepareConnection() }.buttonStyle(.borderedProminent) }
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
                    Metric(label: "Output", value: model.canEdit ? (model.state.outputMode < 2 ? "3.5 mm" : "2.5 mm balanced") : "—")
                }
            }
            HStack(spacing: 18) {
                Panel(title: "On the device", subtitle: "Active EQ and audio settings live on your ES100. After configuring it, you can close this app and keep listening from Bluetooth or USB.") {
                    Label("Hardware audio processing", systemImage: "cpu").font(.system(size: 12)).foregroundStyle(StudioTheme.green)
                }
                Panel(title: "In your library", subtitle: "Save as many EQ presets as you need. Import an Android preferences export or share presets between Macs as JSON.") {
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
            Panel(title: "Analog output", subtitle: "Choose the headphone connection and amplifier mode.") {
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
            }
            HStack(alignment: .top, spacing: 18) {
                Panel(title: "DAC filter", subtitle: "AK4375A reconstruction filter") {
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
                IntegerSlider(title: "Crossfeed", value: model.intBinding(\.crossfeed, .crossfeed, range: 0...10), range: 0...10).disabled(!model.available(.audio, .crossfeed))
                Text("Blend a little of each channel into the other. 0 turns crossfeed off.").font(.caption).foregroundStyle(StudioTheme.secondary)
                Divider().overlay(StudioTheme.border)
                IntegerSlider(title: "DCT level", value: model.intBinding(\.dct, .dct, range: 0...10), range: 0...10).disabled(!model.available(.audio, .dct))
                Text("Radsone’s built-in processing, using the same levels as the Android app.").font(.caption).foregroundStyle(StudioTheme.secondary)
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
                Picker("USB format", selection: model.intBinding(\.usbBits, .usbBits, range: 0...2)) {
                    Text("48 kHz · 16-bit").tag(0)
                    Text("48 kHz · 24-bit (Mac)").tag(1)
                    Text("44.1 / 48 kHz · 16-bit").tag(2)
                }.disabled(!model.available(.info, .usbBits) || !model.state.supportsQ)
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
                SettingToggle(title: "Let the outside in", value: model.boolBinding(\.ambient, .ambient)).disabled(!model.available(.audio, .ambient))
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
                SettingToggle(title: "Battery care", detail: "Use the ES100’s battery-life protection mode.", value: model.boolBinding(\.batteryCare, .batteryCare)).disabled(!model.available(.info, .batteryCare))
                SettingToggle(title: "USB charging", detail: "Turn off to run from the battery while connected by USB.", value: model.boolBinding(\.chargerEnabled, .charger)).disabled(!model.available(.audio, .charger))
                Picker("Auto power", selection: model.intBinding(\.autoPower, .autoPower, range: 0...2)) {
                    Text("Normal").tag(0); Text("Off when charger connects").tag(1); Text("Off when USB power disconnects").tag(2)
                }.disabled(!model.available(.device, .autoPower))
            }
            Panel(title: "Everyday controls") {
                SettingToggle(title: "Reconnect second device", detail: "Restore the second Bluetooth connection automatically.", value: model.boolBinding(\.reconnect, .reconnect)).disabled(!model.available(.info, .reconnect))
                Picker("Status light", selection: model.intBinding(\.led, .led, range: 0...2)) {
                    Text("Color").tag(0); Text("White").tag(1); Text("Off").tag(2)
                }.disabled(!model.available(.info, .led))
                Divider()
                ValueSlider(title: "Maximum volume", value: model.doubleBinding(\.volumeLimit, .volumeLimit, range: -60...6), range: -60...6).disabled(!model.available(.info, .volumeLimit))
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
