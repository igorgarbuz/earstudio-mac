import SwiftUI

enum StudioPage: String, CaseIterable, Identifiable {
    case overview = "Overview", equalizer = "Equalizer", sound = "Sound", input = "Input", ambient = "Ambient & calls", system = "Device settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "hifispeaker"
        case .equalizer: return "slider.vertical.3"
        case .sound: return "waveform"
        case .input: return "antenna.radiowaves.left.and.right"
        case .ambient: return "ear"
        case .system: return "gearshape"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "Your music. Your little studio."
        case .equalizer: return "Shape the sound. Keep the detail."
        case .sound: return "Fine-tune the ES100’s output and processing."
        case .input: return "Bluetooth and USB, configured your way."
        case .ambient: return "Stay in touch with the world around you."
        case .system: return "The small things that make it yours."
        }
    }
}

struct StudioView: View {
    @EnvironmentObject var model: StudioModel
    @State private var page = StudioPage.equalizer
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 211)
            Rectangle().fill(StudioTheme.border).frame(width: 1)
            VStack(spacing: 0) {
                header
                if let message = model.message {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(StudioTheme.green)
                        Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                    }.padding(14).background(StudioTheme.green.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 28).padding(.bottom, 12)
                }
                if !model.canEdit { connectionBanner }
                ScrollView {
                    Group {
                        switch page {
                        case .overview: OverviewView()
                        case .equalizer: EqualizerView()
                        case .sound: SoundView()
                        case .input: InputView()
                        case .ambient: AmbientView()
                        case .system: SystemView()
                        }
                    }.padding(.horizontal, 28).padding(.top, 3).padding(.bottom, 25)
                }
                volumeBar
            }
        }
        .background(StudioTheme.background)
        .frame(minWidth: 1040, minHeight: 760)
        .sheet(isPresented: $model.showConnection) { ConnectionSheet() }
        .sheet(isPresented: $model.showDiagnostics) { DiagnosticsSheet() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<5) { index in
                        Capsule().fill(StudioTheme.green).frame(width: 3, height: [12.0, 25.0, 18.0, 31.0, 12.0][index])
                    }
                }.frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("earstudio").font(.system(size: 21, weight: .medium)).tracking(-0.6)
                    Text("COMPANION").font(.system(size: 8, weight: .medium)).tracking(2.7).foregroundStyle(StudioTheme.secondary)
                }
            }.padding(.horizontal, 23).padding(.top, 50).padding(.bottom, 36)
            Text("YOUR STUDIO").sectionCaption().padding(.horizontal, 25).padding(.bottom, 12)
            ForEach(StudioPage.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).font(.system(size: 15)).frame(width: 22)
                        Text(item.rawValue).font(.system(size: 12, weight: page == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if page == item { Circle().fill(StudioTheme.green).frame(width: 4, height: 4) }
                    }.foregroundStyle(page == item ? StudioTheme.green : StudioTheme.secondary)
                        .padding(.horizontal, 13).padding(.vertical, 13)
                        .background(page == item ? StudioTheme.green.opacity(0.085) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 3)
            }
            Spacer(minLength: 35)
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: "hifispeaker").font(.system(size: 17)).foregroundStyle(StudioTheme.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ES100 / MK2").font(.system(size: 12, weight: .semibold))
                        Text(model.phase.rawValue).font(.system(size: 10)).foregroundStyle(StudioTheme.secondary)
                    }
                }
                Button { model.prepareConnection() } label: {
                    HStack { Text(model.phase == .connected ? "Change device" : "Connect device"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 11, weight: .medium)).padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
            }.padding(15).background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12)).padding(14)
            HStack {
                Button(model.isDemo ? "Exit demo" : "Explore demo") { model.isDemo ? model.disconnect() : model.enterDemo() }
                    .disabled(model.isBusy || model.phase == .connected)
                Spacer()
                Button { model.showDiagnostics = true } label: { Image(systemName: "ellipsis.circle") }.help("Diagnostics")
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(StudioTheme.secondary).padding(.horizontal, 23).padding(.bottom, 22)
        }.background(StudioTheme.sidebar)
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(page.rawValue).font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                Text(page.subtitle).font(.system(size: 12)).foregroundStyle(StudioTheme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                StatusPill(text: model.isDemo ? "DEMO · NO DEVICE" : model.phase.rawValue.uppercased(), color: model.isDemo ? .orange : (model.canEdit ? StudioTheme.green : StudioTheme.secondary))
                if model.state.loaded.contains(.battery) {
                    Label("\(model.state.battery)%", systemImage: model.state.charging ? "battery.100percent.bolt" : "battery.75percent")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(StudioTheme.secondary)
                }
            }
        }.padding(.horizontal, 30).padding(.top, 40).padding(.bottom, 26)
    }
    private var connectionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: model.phase == .confirmation ? "hand.tap" : "antenna.radiowaves.left.and.right").font(.system(size: 18)).foregroundStyle(StudioTheme.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.phase == .confirmation ? "Briefly press the ES100 power button" : (model.isBusy ? model.phase.rawValue + "…" : "Connect your EarStudio to get started"))
                    .font(.system(size: 12, weight: .semibold))
                Text(model.phase == .confirmation ? "Confirm within three minutes. This Mac will remember your device." : "Settings are read from your device when it connects.")
                    .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
            }
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
                Button("Cancel") { model.cancelConfirmation() }
            } else {
                Button("Connect…") { model.prepareConnection() }.buttonStyle(.borderedProminent).tint(StudioTheme.green).foregroundStyle(.black)
            }
        }.padding(16).background(StudioTheme.card, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 28).padding(.bottom, 16)
    }
    private var volumeBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(StudioTheme.border).frame(height: 1)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("OUTPUT VOLUME").sectionCaption()
                    Text(model.canEdit ? model.state.outputName : "No device connected").font(.system(size: 10)).foregroundStyle(StudioTheme.secondary)
                }.frame(width: 160, alignment: .leading)
                Button { model.boolBinding(\.muted, .mute).wrappedValue.toggle() } label: {
                    Image(systemName: model.state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 17)).foregroundStyle(model.state.muted ? StudioTheme.green : StudioTheme.secondary)
                }.buttonStyle(.plain).help(model.state.muted ? "Unmute" : "Mute").accessibilityLabel(model.state.muted ? "Unmute" : "Mute")
                Slider(value: model.doubleBinding(\.volume, .volume, range: -60...6).quantized(0.5), in: -60...6).controlSize(.small).accessibilityLabel("Output volume")
                Text(model.canEdit ? String(format: "%.1f", model.state.volume) : "—").font(.system(size: 23, weight: .light, design: .rounded)).monospacedDigit()
                    .frame(width: 63, alignment: .trailing)
                Text("dB").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                Rectangle().fill(StudioTheme.border).frame(width: 1, height: 28)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(model.isDemo ? "PREVIEW" : (model.pendingCount > 0 ? "SYNCING" : (model.canEdit ? "DEVICE SYNCED" : "OFFLINE")))
                        .font(.system(size: 8, weight: .medium)).tracking(0.8).foregroundStyle(StudioTheme.secondary)
                    Text(model.canEdit ? model.state.inputName : "ES100 / MK2").font(.system(size: 10))
                }.frame(width: 92, alignment: .trailing)
            }.padding(.horizontal, 28).padding(.vertical, 20).disabled(!model.available(.audio))
        }.background(StudioTheme.sidebar)
    }
}

struct ConnectionSheet: View {
    @EnvironmentObject var model: StudioModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Connect your EarStudio").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Turn on your ES100 or MK2 and pair it in macOS Bluetooth settings. If asked, briefly press its power button to authorize this Mac.")
                .font(.callout).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                if model.devices.isEmpty {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 32)).foregroundStyle(StudioTheme.green).padding(.top, 22)
                    Text(model.scanning ? "Searching for EarStudio…" : "No EarStudio devices found yet").font(.callout)
                    Text("Keep the device nearby and close other EarStudio control apps.").font(.caption).foregroundStyle(StudioTheme.secondary).padding(.bottom, 24)
                }
                ForEach(model.devices) { device in
                    HStack {
                        Image(systemName: "hifispeaker").font(.title2).foregroundStyle(StudioTheme.green)
                        VStack(alignment: .leading, spacing: 5) { Text(device.name).fontWeight(.medium); Text(device.paired ? "Paired with this Mac" : "Discovered nearby").font(.caption).foregroundStyle(StudioTheme.secondary) }
                        Spacer()
                        Button("Connect") { model.connect(device) }.buttonStyle(.borderedProminent)
                    }.padding(15).background(StudioTheme.card, in: RoundedRectangle(cornerRadius: 10))
                }
            }.frame(maxWidth: .infinity)
            HStack {
                Button("Bluetooth settings…") { model.openBluetoothSettings() }
                Spacer()
                if model.scanning { ProgressView().controlSize(.small) }
                Button(model.scanning ? "Searching…" : "Search nearby") { model.scan() }.disabled(model.scanning)
            }
        }.padding(28).frame(width: 500).background(StudioTheme.background)
    }
}

struct DiagnosticsSheet: View {
    @EnvironmentObject var model: StudioModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Connection diagnostics").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("\(model.phase.rawValue) · Firmware \(model.state.firmware ?? "unknown")").foregroundStyle(StudioTheme.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    if model.logs.isEmpty { Text("No connection activity yet.").foregroundStyle(StudioTheme.secondary) }
                    ForEach(model.logs) { item in
                        Text(item.date.formatted(date: .omitted, time: .standard) + "  " + item.text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
            }.frame(height: 300).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("Authentication keys are excluded from this log.").font(.caption).foregroundStyle(StudioTheme.secondary)
                Spacer(); Button("Export…") { model.exportDiagnostics() }
            }
        }.padding(25).frame(width: 650).background(StudioTheme.background)
    }
}
