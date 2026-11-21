import SwiftUI
import UniformTypeIdentifiers
import EarStudioCore
import EarStudioSession
import EarStudioUI

struct PhoneEqualizerView: View {
    @EnvironmentObject private var model: IOSStudioModel
    private var session: DeviceSession { model.session }
    @State private var curveFrame: CGRect?

    var body: some View {
        List {
            SessionMessageSection()
            Section {
                Toggle("Equalizer", isOn: session.boolBinding(\.eqEnabled, .eqEnabled))
                    .disabled(!session.available(.eq, .eqEnabled))
                    .accessibilityIdentifier("eq.enabled")
                // Reserve the original row while rendering one curve above the list.
                // Keeping its layout stable avoids scroll jumps when it becomes pinned.
                Color.clear
                    .frame(height: 145)
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .global)
                    } action: { frame in
                        curveFrame = frame
                    }
                Text(session.canEdit ? session.presetName : "Connect to EarStudio to edit the equalizer.")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink {
                    PhonePresetsView()
                } label: { Label("Presets", systemImage: "square.stack") }
                    .frame(minHeight: 44).accessibilityIdentifier("eq.presets")
            } footer: {
                Text("The curve estimates the response. Audio processing happens on your ES100.")
            }
            Section("Preamp") {
                PhoneSlider(title: "Preamp", value: session.doubleBinding(\.preamp, .preamp, range: -12...12, gain: true),
                            range: -12...12, step: 0.1, identifier: "eq.preamp")
                    .disabled(!session.available(.eq, .preamp))
            }
            Section("Ten fixed bands") {
                ForEach(0..<10) { index in
                    PhoneSlider(title: bandTitle(index), value: session.bandBinding(index),
                                range: -12...12, step: 0.1, identifier: "eq.band.\(index)", compact: true)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .disabled(!session.available(.eq, .band))
            Section {
                Picker("Band width", selection: Binding(get: { session.state.q }, set: { session.setQ($0) })) {
                    Text("Wide").tag(2896)
                    Text("Narrow").tag(5791)
                }.disabled(!session.available(.eq, .q))
                Picker("Headroom", selection: Binding(get: { session.state.headroom }, set: {
                    session.setHeadroom($0, compensation: session.state.analogCompensation)
                })) {
                    Text("−6 dB").tag(1); Text("−12 dB").tag(2)
                }.disabled(!session.available(.eq, .headroom))
                Toggle("Analog compensation", isOn: Binding(get: { session.state.analogCompensation }, set: {
                    session.setHeadroom(session.state.headroom, compensation: $0)
                })).disabled(!session.available(.eq, .headroom))
            } header: { Text("Processing") } footer: {
                Text("Headroom makes space for boosted bands; analog compensation restores output level. Some options require newer firmware.")
            }
            Section {
                Button("Reset to flat") { session.applyPreset(.flat) }
                    .frame(minHeight: 44).disabled(!session.available(.eq, .allGains))
                    .accessibilityIdentifier("eq.reset")
            }
        }
        .accessibilityIdentifier("screen.equalizer")
        .overlay(alignment: .top) {
            GeometryReader { viewport in
                if let frame = curveFrame {
                    let origin = viewport.frame(in: .global)
                    let top = frame.minY - origin.minY
                    // Ease in the backdrop over the final 32 points of scrolling.
                    // The curve keeps its size and follows the finger in both directions.
                    let progress = min(1, max(0, 1 - top / 32))
                    let backdropOpacity = progress * progress * (3 - 2 * progress)
                    EQChart(state: session.state, active: session.canEdit && session.state.eqEnabled)
                        .frame(height: 145)
                        .padding(.horizontal, max(0, frame.minX - origin.minX))
                        .padding(.bottom, 8)
                        .background {
                            Rectangle().fill(.regularMaterial).opacity(backdropOpacity)
                        }
                        .overlay(alignment: .bottom) {
                            Divider().opacity(backdropOpacity)
                        }
                        .offset(y: max(0, top))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(session.canEdit && session.state.eqEnabled ? "Estimated equalizer response curve" : "Equalizer bypassed")
                        .accessibilityIdentifier("eq.curve")
                }
            }
        }
        .navigationTitle("Equalizer")
    }
    private func bandTitle(_ index: Int) -> String {
        let frequency = DeviceState.frequencies[index]
        return frequency >= 1_000 ? "\((frequency / 1_000).formatted()) kHz" : "\(frequency.formatted()) Hz"
    }
}

struct PhonePresetsView: View {
    @EnvironmentObject private var model: IOSStudioModel
    @State private var showingSave = false
    @State private var presetName = ""
    @State private var showingImport = false
    @State private var showingExport = false
    @State private var exportDocument = PresetDocument(data: Data())
    private var session: DeviceSession { model.session }

    var body: some View {
        List {
            SessionMessageSection()
            Section {
                Button {
                    presetName = session.presetName == "Device settings" ? "" : session.presetName
                    showingSave = true
                } label: { Label("Save current preset", systemImage: "plus") }
                    .frame(minHeight: 44).disabled(!session.available(.eq))
                    .accessibilityIdentifier("presets.save")
                Button { showingImport = true } label: { Label("Import presets", systemImage: "square.and.arrow.down") }
                    .frame(minHeight: 44)
                Button {
                    do {
                        exportDocument = PresetDocument(data: try session.exportPresets())
                        showingExport = true
                    } catch { session.message = error.localizedDescription }
                } label: { Label("Export presets", systemImage: "square.and.arrow.up") }
                    .frame(minHeight: 44).disabled(session.presets.isEmpty && !session.available(.eq))
            } footer: {
                Text("Presets are saved on this iPhone. Import JSON or an exported Android preferences XML file. Importing does not change your device.")
            }
            Section("Your presets") {
                if session.presets.isEmpty { Text("No saved presets yet.").foregroundStyle(.secondary) }
                ForEach(session.presets) { preset in
                    Button { session.applyPreset(preset) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.name).foregroundStyle(.primary)
                            Text("Preamp \(preset.preamp.formatted()) dB").font(.caption).foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }
                    .disabled(!session.available(.eq, .allGains))
                    .swipeActions { Button("Delete", role: .destructive) { session.deletePreset(preset.id) } }
                }
            }
            Section {
                ForEach(FactoryEQPreset.all) { preset in
                    Button(preset.name) { session.applyFactoryPreset(preset) }
                        .frame(minHeight: 44)
                        .disabled(!session.available(.eq, .allGains))
                }
            } header: { Text("Factory presets") } footer: {
                Text("Factory curves change band gains and preamp, preserving your processing options.")
            }
        }
        .navigationTitle("Presets")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Save preset", isPresented: $showingSave) {
            TextField("Preset name", text: $presetName)
                .accessibilityIdentifier("presets.name")
            Button("Save") { session.savePreset(name: presetName) }
                .accessibilityIdentifier("presets.confirm")
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.json, .xml]) { result in
            do {
                let url = try result.get()
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 1_048_576 else { throw PresetError.tooLarge }
                try session.importPresets(from: Data(contentsOf: url), isAndroidXML: url.pathExtension.lowercased() == "xml")
            } catch { session.message = error.localizedDescription }
        }
        .fileExporter(isPresented: $showingExport, document: exportDocument, contentType: .json,
                      defaultFilename: "EarStudio Presets") { result in
            if case .failure(let error) = result { session.message = error.localizedDescription }
        }
        .accessibilityIdentifier("screen.presets")
    }
}

struct PresetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
