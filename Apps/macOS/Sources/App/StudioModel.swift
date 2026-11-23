import AppKit
import Combine
import IOBluetooth
import SwiftUI
import UniformTypeIdentifiers
import EarStudioCore
import EarStudioSession
import EarStudioUI

/// macOS presentation and integration. Device behavior lives in DeviceSession.
final class StudioModel: ObservableObject {
    let session: DeviceSession
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var scanning = false
    @Published var showConnection = false
    @Published var showDiagnostics = false
    private var discovery: BluetoothTransport?
    private var subscriptions = Set<AnyCancellable>()
    private let makeTransport: () -> ControlTransport
    private let resetBluetooth: (IOBluetoothDevice, @escaping (IOReturn) -> Void) -> Void

    init(demo: Bool = false, makeTransport: @escaping () -> ControlTransport = { BluetoothTransport() },
         saveDeviceKey: @escaping (UInt16, String) -> Bool = { DeviceKeyStore.shared.save($0, for: $1) },
         readDeviceKey: @escaping (String) -> UInt16 = { DeviceKeyStore.shared.read($0) },
         forgetDeviceKey: @escaping (String) -> Bool = { DeviceKeyStore.shared.forget($0) },
         resetBluetooth: @escaping (IOBluetoothDevice, @escaping (IOReturn) -> Void) -> Void = { device, done in
             DispatchQueue.global(qos: .userInitiated).async {
                 let result = BluetoothLinkReset.reconnect(device)
                 DispatchQueue.main.async { done(result) }
             }
         }) {
        self.makeTransport = makeTransport
        self.resetBluetooth = resetBluetooth
        session = DeviceSession(demo: demo,
            defaults: demo ? UserDefaults(suiteName: "EarStudioCompanion.Demo")! : .standard,
            saveDeviceKey: saveDeviceKey, readDeviceKey: readDeviceKey, forgetDeviceKey: forgetDeviceKey)
        session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        session.$phase.dropFirst().sink { [weak self] phase in
            if phase == .disconnected { self?.stopDiscovery() }
        }.store(in: &subscriptions)
    }

    var state: DeviceState { session.state }
    var phase: ConnectionPhase { session.phase }
    var deviceName: String { session.deviceName }
    var address: String { session.address }
    var pendingCount: Int { session.pendingCount }
    var logs: [LogEntry] { session.logs }
    var presets: [EQPreset] { session.presets }
    var message: String? { get { session.message } set { session.message = newValue } }
    var presetName: String { session.presetName }
    var isDemo: Bool { session.isDemo }
    var hasSelectedDevice: Bool { session.hasSelectedDevice }
    var canEdit: Bool { session.canEdit }
    var isBusy: Bool { session.isBusy }

    func requestConnection() {
        guard !isBusy else { return }
        if phase == .disconnected, hasSelectedDevice {
            stopDiscovery(); showConnection = false
            session.reconnectSelectedDevice()
        } else { prepareConnection() }
    }
    func prepareConnection() {
        guard !isBusy else { return }
        showConnection = true
        if discovery == nil {
            let scanner = BluetoothTransport()
            scanner.onDevices = { [weak self] in self?.devices = $0 }
            scanner.onScanFinished = { [weak self] in self?.scanning = false }
            scanner.onError = { [weak self] in self?.message = $0.message }
            discovery = scanner
        }
        discovery?.loadPaired()
    }
    func scan() { scanning = true; discovery?.scan() }
    private func stopDiscovery() { discovery?.stopScan(); scanning = false }
    func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { NSWorkspace.shared.open(url) }
    }
    func connect(_ device: DiscoveredDevice) {
        stopDiscovery(); showConnection = false
        let makeTransport = self.makeTransport
        let resetBluetooth = self.resetBluetooth
        session.connect(DeviceConnection(id: device.id, name: device.name,
            makeTransport: { MacSessionTransport(transport: makeTransport(), device: device.device) },
            resetLink: { completion in
                resetBluetooth(device.device) { result in
                    if result == 0 { completion(.success(())) }
                    else { completion(.failure(BluetoothResetError(status: result))) }
                }
            }))
    }
    func disconnect(completion: @escaping () -> Void = {}) { stopDiscovery(); session.disconnect(completion: completion) }
    func cancelConfirmation() { session.cancelConfirmation() }
    func forgetKey() { session.forgetKey() }
    func refresh() { session.refresh() }
    func available(_ group: StateGroup, _ command: DeviceCommand? = nil) -> Bool { session.available(group, command) }
    func doubleBinding(_ path: WritableKeyPath<DeviceState, Double>, _ command: DeviceCommand, range: ClosedRange<Double>, gain: Bool = false) -> Binding<Double> {
        session.doubleBinding(path, command, range: range, gain: gain)
    }
    func boolBinding(_ path: WritableKeyPath<DeviceState, Bool>, _ command: DeviceCommand) -> Binding<Bool> { session.boolBinding(path, command) }
    func intBinding(_ path: WritableKeyPath<DeviceState, Int>, _ command: DeviceCommand, range: ClosedRange<Int>) -> Binding<Int> { session.intBinding(path, command, range: range) }
    func bandBinding(_ index: Int) -> Binding<Double> { session.bandBinding(index) }
    func setQ(_ value: Int) { session.setQ(value) }
    func setHeadroom(_ mode: Int, compensation: Bool) { session.setHeadroom(mode, compensation: compensation) }
    func setOutput(_ mode: Int) { session.setOutput(mode) }
    func setTrim(left: Double, right: Double) { session.setTrim(left: left, right: right) }
    func setJitter(usb: Bool, bluetooth: Bool) { session.setJitter(usb: usb, bluetooth: bluetooth) }
    func setCodecs(aac: Bool, aptx: Bool, hd: Bool) { session.setCodecs(aac: aac, aptx: aptx, hd: hd) }
    func setMic(ambient: Bool, preamp: Bool, gain: Int) { session.setMic(ambient: ambient, preamp: preamp, gain: gain) }
    func applyFactoryPreset(_ preset: FactoryEQPreset) { session.applyFactoryPreset(preset) }
    func applyPreset(_ preset: EQPreset) { session.applyPreset(preset) }
    func savePreset(name: String) { session.savePreset(name: name) }
    func deletePreset(_ id: UUID) { session.deletePreset(id) }

    func importPresets() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json, .xml]; panel.allowsMultipleSelection = false
        panel.message = "Import EarStudio presets or an exported Android SharedPreferences XML file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw PresetError.tooLarge }
            try session.importPresets(from: Data(contentsOf: url), isAndroidXML: url.pathExtension.lowercased() == "xml")
        } catch { message = error.localizedDescription }
    }
    func exportPresets() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "EarStudio Presets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try session.exportPresets().write(to: url, options: .atomic) }
        catch { message = error.localizedDescription }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "EarStudio Diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = "ES100 Control \(AppMetadata.version) (\(AppMetadata.build))\nFirmware: \(state.firmware ?? "unknown")\n\(logs.map { "\($0.date.ISO8601Format()) \($0.text)" }.joined(separator: "\n"))\n"
        do { try content.write(to: url, atomically: true, encoding: .utf8) } catch { message = error.localizedDescription }
    }
}

private struct BluetoothResetError: LocalizedError {
    let status: IOReturn
    var errorDescription: String? {
        "macOS could not reset the Bluetooth link (\(status)). Disconnect and reconnect EarStudio in Bluetooth settings, then connect here again."
    }
}
