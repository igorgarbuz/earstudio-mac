import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject var model: StudioModel
    @State private var saving = false
    @State private var newName = ""
    var body: some View {
        VStack(spacing: 18) {
            Panel(title: "") {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("10-BAND EQUALIZER").sectionCaption()
                        Text(model.presetName).font(.system(size: 18, weight: .medium))
                    }
                    Spacer()
                    Menu {
                        Section("Factory presets") {
                            ForEach(FactoryEQPreset.all) { preset in
                                Button(preset.name) { model.applyFactoryPreset(preset) }.disabled(!model.available(.eq, .allGains))
                            }
                        }
                        if !model.presets.isEmpty {
                            Section("Saved presets") {
                                ForEach(model.presets) { preset in
                                    Button(preset.name) { model.applyPreset(preset) }.disabled(!model.available(.eq, .allGains))
                                }
                            }
                        }
                        Divider()
                        Button("Save current as preset…") { newName = ""; saving = true }.disabled(!model.available(.eq))
                        Button("Import presets…") { model.importPresets() }
                        Button("Export presets…") { model.exportPresets() }
                        if !model.presets.isEmpty {
                            Menu("Delete saved preset") { ForEach(model.presets) { p in Button(p.name, role: .destructive) { model.deletePreset(p.id) } } }
                        }
                    } label: { Label("Presets", systemImage: "square.stack") }
                        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 12)).padding(.trailing, 16)
                    Toggle("EQ", isOn: model.boolBinding(\.eqEnabled, .eqEnabled)).toggleStyle(.switch).controlSize(.small).font(.system(size: 12, weight: .medium)).disabled(!model.available(.eq, .eqEnabled))
                }
                EQChart(state: model.state, active: model.canEdit && model.state.eqEnabled)
                    .frame(height: 151)
                HStack {
                    Text("FREQUENCY · Hz").font(.system(size: 8, weight: .medium)).tracking(1.1)
                    Spacer()
                    Text("Estimated response · device processes the audio").font(.system(size: 9))
                }.foregroundStyle(StudioTheme.secondary)
                Rectangle().fill(StudioTheme.border).frame(height: 1)
                HStack(spacing: 5) {
                    ForEach(0..<10, id: \.self) { index in
                        EQBand(label: DeviceState.bandLabels[index], value: model.bandBinding(index))
                    }
                }.disabled(!model.available(.eq, .band)).opacity(model.state.eqEnabled ? 1 : 0.5)
                HStack {
                    Text("±12 dB").font(.system(size: 9)).foregroundStyle(StudioTheme.secondary)
                    Spacer()
                    Button("Reset to flat") { model.applyPreset(.flat) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(StudioTheme.secondary).disabled(!model.available(.eq, .allGains))
                }
            }
            HStack(alignment: .top, spacing: 18) {
                Panel(title: "Preamp", subtitle: "Level before equalization") {
                    ValueSlider(title: "Gain", value: model.doubleBinding(\.preamp, .preamp, range: -12...12, gain: true), range: -12...12, step: 0.1)
                        .disabled(!model.available(.eq, .preamp))
                    HStack { Text("−12 dB"); Spacer(); Text("+12 dB") }.font(.system(size: 9)).foregroundStyle(StudioTheme.secondary)
                }
                Panel(title: "Filter width", subtitle: model.state.supportsQ ? "The original EarStudio Q options" : "Requires firmware 1.4.3 or newer") {
                    Picker("Filter width", selection: Binding(get: { model.state.q }, set: model.setQ)) {
                        Text("Wide · 0.7071").tag(2896)
                        Text("Narrow · 1.4142").tag(5791)
                    }.pickerStyle(.segmented).labelsHidden().disabled(!model.available(.eq, .q) || !model.state.supportsQ)
                    Text("Fixed center frequencies, adjustable gain and Q.").font(.system(size: 10)).foregroundStyle(StudioTheme.secondary)
                }
            }
            Panel(title: "Headroom", subtitle: "Reserve digital headroom for EQ boosts. Available on firmware 1.4.0 and later.") {
                InfoButton(topic: .equalizer)
                HStack(spacing: 35) {
                    Picker("Digital headroom", selection: Binding(get: { model.state.headroom }, set: { model.setHeadroom($0, compensation: model.state.analogCompensation) })) {
                        Text("−6 dB").tag(1); Text("−12 dB").tag(2)
                    }.pickerStyle(.segmented).frame(width: 195).labelsHidden()
                    SettingToggle(title: "+6 dB analog compensation", value: Binding(get: { model.state.analogCompensation }, set: { model.setHeadroom(model.state.headroom, compensation: $0) }))
                }.disabled(!model.available(.eq, .headroom) || !model.state.supportsHeadroom)
            }
        }
        .sheet(isPresented: $saving) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Save EQ preset").font(.title2.weight(.semibold))
                Text("Save the ten bands, preamp, Q, and headroom settings together.").font(.callout).foregroundStyle(StudioTheme.secondary)
                TextField("Preset name", text: $newName).textFieldStyle(.roundedBorder).onSubmit { save() }
                HStack { Spacer(); Button("Cancel") { saving = false }.keyboardShortcut(.cancelAction); Button("Save preset") { save() }.keyboardShortcut(.defaultAction).disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(28).frame(width: 410).background(StudioTheme.background)
        }
    }
    private func save() {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.savePreset(name: newName); saving = false
    }
}

struct EQBand: View {
    let label: String
    @Binding var value: Double
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    @State private var dragStartGain: Double?
    var body: some View {
        VStack(spacing: 9) {
            TextField("Gain at \(label) Hz", value: $value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.plain).multilineTextAlignment(.center).font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(StudioTheme.green).padding(.vertical, 5).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 5))
                .frame(width: 48).accessibilityLabel("Gain at \(label) Hz in dB")
            GeometryReader { proxy in
                let height = proxy.size.height - 16
                let y = 8 + (12 - value) / 24 * height
                ZStack(alignment: .top) {
                    Capsule().fill(.black.opacity(0.35)).frame(width: 4, height: height).offset(y: 8)
                    ForEach(0..<5) { index in
                        Rectangle().fill(index == 2 ? .white.opacity(0.3) : .white.opacity(0.08))
                            .frame(width: index == 2 ? 22 : 12, height: 1).offset(y: 8 + Double(index) / 4 * height)
                    }
                    Capsule().fill(StudioTheme.green.opacity(0.45)).frame(width: 4, height: max(1, abs(y - proxy.size.height / 2)))
                        .offset(y: min(y, proxy.size.height / 2))
                    RoundedRectangle(cornerRadius: 4).fill(StudioTheme.green)
                        .frame(width: 25, height: 10).shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                        .overlay(Capsule().fill(.black.opacity(0.3)).frame(width: 13, height: 1))
                        .offset(y: y - 5)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .gesture(gainDrag(in: proxy, trackHeight: height, thumbY: y))
                    .onTapGesture(count: 2) { if enabled { value = 0 } }
            }.frame(height: 132)
                .focusable(enabled).focused($focused).focusEffectDisabled()
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? StudioTheme.green.opacity(0.4) : .clear))
                .onKeyPress(.upArrow) { guard enabled else { return .ignored }; value = min(12, value + 0.1); return .handled }
                .onKeyPress(.downArrow) { guard enabled else { return .ignored }; value = max(-12, value - 0.1); return .handled }
                .accessibilityElement(children: .ignore).accessibilityLabel("\(label) hertz")
                .accessibilityValue(String(format: "%.1f decibels", value))
                .accessibilityAdjustableAction { direction in
                    guard enabled else { return }
                    if direction == .increment { value = min(12, value + 0.1) } else if direction == .decrement { value = max(-12, value - 0.1) }
                }
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(StudioTheme.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func gainDrag(in geometry: GeometryProxy, trackHeight: CGFloat, thumbY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { event in
            guard enabled else { return }
            focused = true
            let height = Double(trackHeight)
            if dragStartGain == nil {
                let startY = Double(event.startLocation.y - geometry.frame(in: .global).minY)
                // Grabbing the thumb keeps its gain; clicking the track seeks.
                dragStartGain = abs(startY - Double(thumbY)) <= 8 ? value : min(12, max(-12, 12 - (startY - 8) / height * 24))
            }
            // Readback or a message can move the track during a drag. Using
            // screen-space translation from the initial gain prevents a
            // layout/value update from jumping the thumb to an endpoint.
            guard let startGain = dragStartGain else { return }
            let gain = startGain - Double(event.translation.height) / height * 24
            value = (min(12, max(-12, gain)) * 10).rounded() / 10
        }.onEnded { _ in dragStartGain = nil }
    }
}

struct EQChart: View {
    let state: DeviceState
    var active: Bool
    var body: some View {
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
