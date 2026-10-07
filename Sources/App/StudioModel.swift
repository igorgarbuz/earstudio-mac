import AppKit
import IOBluetooth
import SwiftUI
import UniformTypeIdentifiers

enum ConnectionPhase: String {
    case disconnected = "Not connected"
    case connecting = "Connecting"
    case recovering = "Reconnecting Bluetooth"
    case authenticating = "Authenticating"
    case confirmation = "Press the power button"
    case syncing = "Reading device"
    case connected = "Connected"
    case demo = "Demo mode"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}

final class StudioModel: ObservableObject {
    @Published private(set) var state = DeviceState()
    @Published private(set) var phase = ConnectionPhase.disconnected
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var scanning = false
    @Published private(set) var deviceName = "EarStudio ES100"
    @Published private(set) var address = ""
    @Published private(set) var pendingCount = 0
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var presets: [EQPreset] = []
    @Published var message: String?
    @Published var showConnection = false
    @Published var showDiagnostics = false
    @Published var presetName = "Custom"
    @Published private(set) var canRecoverBluetooth = false
    private var transport: ControlTransport?
    private var closingTransport: ControlTransport?
    private let makeTransport: () -> ControlTransport
    private let saveDeviceKey: (UInt16, String) -> Bool
    private let resetBluetooth: (IOBluetoothDevice, @escaping (IOReturn) -> Void) -> Void
    private var selectedDevice: DiscoveredDevice?
    private var discovery: BluetoothTransport?
    private var decoder = GAIAStreamDecoder()
    private var queue = CommandQueue()
    private var confirmed = DeviceState()
    private var effects: [UUID: (inout DeviceState) -> Void] = [:]
    private var timer: Timer?
    private var authTimer: Timer?
    private var syncTimer: Timer?
    private var refreshTimer: Timer?
    private var flushWork: DispatchWorkItem?
    private var readbackWork: DispatchWorkItem?
    private var needsRefresh: Set<DeviceCommand> = []
    private var unsupported: Set<DeviceCommand> = []
    private var generation = UUID()
    private var isAuthenticated = false
    private let defaults: UserDefaults

    init(demo: Bool = false, makeTransport: @escaping () -> ControlTransport = { BluetoothTransport() },
         saveDeviceKey: @escaping (UInt16, String) -> Bool = { DeviceKeyStore.save($0, for: $1) },
         resetBluetooth: @escaping (IOBluetoothDevice, @escaping (IOReturn) -> Void) -> Void = { device, done in
             // This SDK call is synchronous. Keep the main run loop available
             // for Bluetooth callbacks and cancellation while it closes audio.
             DispatchQueue.global(qos: .userInitiated).async {
                 let result = device.closeConnection()
                 DispatchQueue.main.async { done(result) }
             }
         }) {
        self.makeTransport = makeTransport
        self.saveDeviceKey = saveDeviceKey
        self.resetBluetooth = resetBluetooth
        defaults = demo ? UserDefaults(suiteName: "EarStudioCompanion.Demo")! : .standard
        if let data = defaults.data(forKey: "presets"), let loaded = try? PresetFile.decode(data) { presets = loaded }
        if demo { enterDemo() }
    }
    var isDemo: Bool { phase == .demo }
    var canEdit: Bool { phase == .connected || isDemo }
    var isBusy: Bool { [.connecting, .recovering, .authenticating, .confirmation, .syncing].contains(phase) }
    func available(_ group: StateGroup, _ command: DeviceCommand? = nil) -> Bool {
        guard canEdit, state.loaded.contains(group) else { return false }
        guard let command else { return true }
        return !unsupported.contains(command) && command.supported(by: state)
            && (command.confirmationReadback.map { !unsupported.contains($0) } ?? true)
            && (command.stateGroup.map { state.loaded.contains($0) } ?? true)
    }

    func prepareConnection() {
        showConnection = true
        if discovery == nil {
            let scanner = BluetoothTransport()
            scanner.onDevices = { [weak self] in self?.devices = $0 }
            scanner.onScanFinished = { [weak self] in self?.scanning = false }
            scanner.onError = { [weak self] in self?.message = $0 }
            discovery = scanner
        }
        discovery?.loadPaired()
    }
    func scan() { scanning = true; discovery?.scan() }
    func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { NSWorkspace.shared.open(url) }
    }
    func connect(_ device: DiscoveredDevice) {
        // Let the previous control channel finish closing before opening another.
        let request = UUID()
        disconnect { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == request else { return }
                self.startConnection(device)
            }
        }
        generation = request; phase = .connecting; message = nil; showConnection = false
    }
    private func startConnection(_ device: DiscoveredDevice) {
        generation = UUID()
        let current = generation
        deviceName = device.name; address = device.id
        selectedDevice = device; canRecoverBluetooth = false
        phase = .connecting; message = nil; showConnection = false
        confirmed = DeviceState(); state = confirmed; presetName = "Device settings"
        let link = makeTransport()
        link.onDiagnostic = { [weak self] in self?.log($0) }
        link.onOpen = { [weak self] in
            guard let self, self.generation == current else { return }
            self.phase = .authenticating
            self.log("Control channel opened. Authenticating.")
            self.sendNow(.authenticate, Wire.u16(DeviceKeyStore.read(self.address)))
            self.authTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
                self?.connectionFailed("Device confirmation timed out. Reconnect and briefly press the ES100 power button when prompted.")
            }
        }
        link.onData = { [weak self] in
            guard let self, self.generation == current else { return }; self.receive($0)
        }
        link.onClose = { [weak self] in
            guard let self, self.generation == current else { return }
            self.disconnect(); self.message = "ES100 disconnected. Your saved presets are still available."
        }
        link.onError = { [weak self] in
            guard let self, self.generation == current else { return }
            let controlOpenFailed = self.phase == .connecting && !$0.contains("Another")
            self.connectionFailed($0)
            self.canRecoverBluetooth = controlOpenFailed
        }
        transport = link; link.connect(device.device)
    }
    func disconnect(completion: @escaping () -> Void = {}) {
        generation = UUID()
        timer?.invalidate(); authTimer?.invalidate(); syncTimer?.invalidate(); refreshTimer?.invalidate(); flushWork?.cancel(); readbackWork?.cancel()
        timer = nil; authTimer = nil; refreshTimer = nil
        let previous = transport ?? closingTransport
        transport = nil; closingTransport = previous
        discovery?.stopScan(); scanning = false
        queue.reset(); effects.removeAll(); needsRefresh.removeAll(); unsupported.removeAll(); decoder.reset()
        pendingCount = 0; isAuthenticated = false; phase = .disconnected
        canRecoverBluetooth = false
        confirmed = DeviceState(); state = confirmed
        if let previous {
            previous.close { [weak self, weak previous] in
                if self?.closingTransport === previous { self?.closingTransport = nil }
                completion()
            }
        }
        else { completion() }
    }
    /// Explicit recovery for the stuck macOS/ES100 RFCOMM session. This closes
    /// the device's baseband link, briefly interrupting its Bluetooth audio.
    /// It never retries a setting write or removes pairing/confirmation keys.
    func recoverBluetoothConnection() {
        guard canRecoverBluetooth, let selectedDevice, phase == .disconnected else { return }
        let request = UUID()
        disconnect { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == request else { return }
                self.log("Resetting the EarStudio Bluetooth link; audio will briefly disconnect.")
                self.timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                    guard let self, self.generation == request else { return }
                    self.connectionFailed("macOS did not finish resetting the Bluetooth link. Disconnect and reconnect EarStudio in Bluetooth settings, then try again.")
                    self.canRecoverBluetooth = true
                }
                self.resetBluetooth(selectedDevice.device) { [weak self] result in
                    guard let self, self.generation == request else { return }
                    self.timer?.invalidate(); self.timer = nil
                    self.log("Bluetooth link reset completed (\(result)).")
                    guard result == 0 else {
                        self.connectionFailed("macOS could not reset the Bluetooth link (\(result)). Disconnect and reconnect EarStudio in Bluetooth settings, then connect here again.")
                        self.canRecoverBluetooth = true
                        return
                    }
                    self.startConnection(selectedDevice)
                }
            }
        }
        generation = request; phase = .recovering; message = nil
    }
    func cancelConfirmation() {
        if phase == .confirmation { sendNow(.cancelAuthentication) }
        disconnect()
    }
    func enterDemo() {
        disconnect(); phase = .demo; deviceName = "EarStudio ES100"; address = ""
        confirmed = .demo; state = confirmed; presetName = "Custom"
        message = nil; showConnection = false
    }
    func forgetKey() {
        guard !address.isEmpty else { return }
        DeviceKeyStore.forget(address); disconnect()
        message = "Saved device confirmation removed. Press the ES100 power button on your next connection."
    }
    private func connectionFailed(_ text: String) { log(text); disconnect(); message = text }
    private func sendNow(_ command: DeviceCommand, _ payload: [UInt8] = []) {
        _ = transport?.send(command.packet(payload).encoded())
    }
    private func receive(_ data: Data) {
        for packet in decoder.append(data) {
            guard packet.vendor == GAIAPacket.earStudioVendor, packet.isAcknowledgement, let status = packet.status else { continue }
            // Never include a device authentication key in diagnostic output.
            log(String(format: "← %04X · status %d · %d bytes", packet.id, status, packet.payload.count))
            if packet.id == 0x0302, status == 0 {
                phase = .confirmation
                continue
            }
            if packet.id == 0x0303, status == 0 {
                guard packet.payload.count >= 3 else { continue }
                if !saveDeviceKey(Wire.readU16(packet.payload, 1), address) {
                    message = "Connected, but the confirmation key could not be saved in Keychain. You may need to confirm again next time."
                }
                authTimer?.invalidate(); authTimer = nil
                isAuthenticated = true; phase = .syncing
                syncTimer?.invalidate()
                syncTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
                    guard let self, self.phase == .syncing else { return }
                    self.connectionFailed("ES100 did not return all required settings. Reconnect, or export diagnostics to investigate firmware compatibility.")
                }
                refresh()
                continue
            }
            if packet.id == 0x0304 {
                connectionFailed("ES100 declined the connection. Reconnect and press its power button when prompted."); return
            }
            if packet.id == DeviceCommand.authenticate.rawValue, status != 0 {
                connectionFailed("Device authentication failed (status \(status))."); return
            }
            let finished = queue.acknowledge(packet)
            let isReadback = finished?.command.confirmationReadback?.rawValue == packet.id
            if finished != nil { timer?.invalidate(); timer = nil; readbackWork?.cancel(); readbackWork = nil }
            if let finished, status != 0 {
                let rejected = isReadback ? (finished.command.confirmationReadback ?? finished.command) : finished.command
                if status == 1 { unsupported.insert(rejected) }
                commandFailed("ES100 rejected \(commandName(rejected)) (status \(status)). Settings have been restored to their last confirmed values.")
                continue
            }
            if let finished, isReadback, !finished.command.hasReadbackFields(in: packet) {
                commandFailed("The device returned an incomplete \(commandName(finished.command.confirmationReadback!)) reply. Use Refresh to check its settings.")
                continue
            }
            if let finished {
                let effect = effects.removeValue(forKey: finished.token)
                if !isReadback {
                    effect?(&confirmed)
                    if let refresh = finished.command.refresh { needsRefresh.insert(refresh) }
                }
            }
            let applied = confirmed.apply(packet)
            if let finished, (finished.command.isRead || isReadback), !applied {
                let query = isReadback ? (finished.command.confirmationReadback ?? finished.command) : finished.command
                commandFailed("The device returned an incomplete \(commandName(query)) reply. Reconnect or export diagnostics to check firmware compatibility.")
                continue
            }
            if let finished, isReadback, !finished.command.matchesReadback(finished.payload, state: confirmed) {
                let setting = finished.command.confirmationReadback == .eq ? "equalizer" : commandName(finished.command)
                commandFailed("ES100 did not apply the \(setting) change. The controls now show the settings read from your device.")
                continue
            }
            rebuildState()
            if isAuthenticated, phase == .syncing, confirmed.firmware != nil, confirmed.loaded.isSuperset(of: [.audio, .eq, .info]) {
                phase = .connected
                syncTimer?.invalidate(); syncTimer = nil
                refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    guard let self, self.phase == .connected, self.pendingCount == 0 else { return }
                    self.enqueue(.battery)
                }
            }
            pump()
        }
    }
    func refresh() {
        guard isAuthenticated else { return }
        // Read firmware first; it determines the layouts of information and EQ.
        for command: DeviceCommand in [.deviceDetails, .deviceInfo, .state, .battery, .eq] { enqueue(command, start: false) }
        pump()
    }
    private func enqueue(_ command: DeviceCommand, _ payload: [UInt8] = [], start: Bool = true) {
        guard !unsupported.contains(command) else { return }
        queue.enqueue(.init(command: command, payload: payload, key: "read-\(command.rawValue)"))
        if start { pump() }
    }
    private func pump() {
        guard isAuthenticated else { return }
        if queue.inFlight == nil, queue.pending.isEmpty, !needsRefresh.isEmpty {
            let queries = needsRefresh.sorted { $0.rawValue < $1.rawValue }; needsRefresh.removeAll()
            for query in queries { enqueue(query, start: false) }
        }
        pendingCount = queue.pending.count + (queue.inFlight == nil ? 0 : 1)
        guard let item = queue.next() else { return }
        pendingCount = queue.pending.count + 1
        log(String(format: "→ %04X · %d bytes", item.command.rawValue, item.payload.count))
        let current = generation
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self, self.generation == current, self.queue.inFlight?.token == item.token else { return }
            let setting = item.command.confirmationReadback == .eq ? "equalizer" : self.commandName(item.command)
            let text = item.command.confirmationReadback == nil
                ? "No reply to \(self.commandName(item.command)). Check the device connection, then use Refresh."
                : "Could not read back the \(setting) settings. The change may have reached ES100. Use Refresh to check."
            self.commandFailed(text)
        }
        if transport?.send(item.packet.encoded()) != true {
            if generation == current { connectionFailed("The control channel is no longer writable. Reconnect to ES100.") }
            return
        }
        if item.command.confirmationReadback != nil {
            // Leave a short settling interval, then query even if no write ACK arrives.
            // Keep this transaction in flight so later edits cannot overtake its readback.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.generation == current,
                      let query = self.queue.beginReadback(for: item.token) else { return }
                self.log(String(format: "→ %04X · 0 bytes · verifying %@", query.rawValue, self.commandName(item.command)))
                if self.transport?.send(query.packet().encoded()) != true, self.generation == current {
                    self.connectionFailed("The control channel is no longer writable. Reconnect to ES100.")
                }
            }
            readbackWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }
    private func commandFailed(_ text: String) {
        if phase == .syncing { connectionFailed(text); return }
        timer?.invalidate(); timer = nil; flushWork?.cancel(); readbackWork?.cancel(); readbackWork = nil
        queue.reset(); effects.removeAll(); needsRefresh.removeAll(); pendingCount = 0
        rebuildState(); message = text; log(text)
        // No automatic retries: a volume or power change may have reached the device.
    }
    private func rebuildState() {
        var next = confirmed
        if let item = queue.inFlight { effects[item.token]?(&next) }
        for item in queue.pending { effects[item.token]?(&next) }
        state = next
    }
    func change(_ command: DeviceCommand, payload: [UInt8], key: String? = nil, mutate: @escaping (inout DeviceState) -> Void) {
        guard let group = command.stateGroup, available(group, command) else { return }
        if command == .usbBits, !state.supportsQ, payload.first == 2 { return }
        if isDemo { mutate(&confirmed); state = confirmed; return }
        let commandKey = key ?? "set-\(command.rawValue)"
        for old in queue.pending where old.key == commandKey { effects.removeValue(forKey: old.token) }
        let item = CommandQueue.Item(command: command, payload: payload, key: commandKey)
        effects[item.token] = mutate
        queue.enqueue(item); rebuildState()
        pendingCount = queue.pending.count + (queue.inFlight == nil ? 0 : 1)
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pump() }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func doubleBinding(_ path: WritableKeyPath<DeviceState, Double>, _ command: DeviceCommand, range: ClosedRange<Double>, gain: Bool = false) -> Binding<Double> {
        Binding(get: { self.state[keyPath: path] }, set: { value in
            guard value.isFinite else { return }
            var value = min(range.upperBound, max(range.lowerBound, value))
            if command == .volume, self.state.supportsHeadroom, self.state.loaded.contains(.info) { value = min(value, self.state.volumeLimit) }
            self.change(command, payload: gain ? [Wire.gain(value)] : Wire.volume(value)) { $0[keyPath: path] = value }
            if command == .preamp { self.presetName = "Custom" }
        })
    }
    func boolBinding(_ path: WritableKeyPath<DeviceState, Bool>, _ command: DeviceCommand) -> Binding<Bool> {
        Binding(get: { self.state[keyPath: path] }, set: { value in
            self.change(command, payload: [value ? 1 : 0]) { $0[keyPath: path] = value }
        })
    }
    func intBinding(_ path: WritableKeyPath<DeviceState, Int>, _ command: DeviceCommand, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { self.state[keyPath: path] }, set: { value in
            let value = min(range.upperBound, max(range.lowerBound, value))
            self.change(command, payload: [UInt8(value)]) { $0[keyPath: path] = value }
        })
    }
    func bandBinding(_ index: Int) -> Binding<Double> {
        Binding(get: { self.state.bands[index] }, set: { value in
            guard value.isFinite else { return }
            let value = (min(12, max(-12, value)) * 10).rounded() / 10
            self.change(.band, payload: Wire.bandGain(at: index, gain: value), key: "band-\(index)") { $0.bands[index] = value }
            self.presetName = "Custom"
        })
    }
    func setQ(_ value: Int) {
        guard [2896, 5791].contains(value), state.supportsQ else { return }
        change(.q, payload: Wire.u16(UInt16(value))) { $0.q = value }
        if canEdit { presetName = "Custom" }
    }
    func setHeadroom(_ mode: Int, compensation: Bool) {
        guard [1, 2].contains(mode), state.supportsHeadroom else { return }
        change(.headroom, payload: [UInt8(mode | (compensation ? 16 : 0))]) { $0.headroom = mode; $0.analogCompensation = compensation }
        if canEdit { presetName = "Custom" }
    }
    func setOutput(_ mode: Int) {
        guard (0...3).contains(mode), !state.outputLocked else { return }
        let single = mode < 2, high = mode % 2 == 1
        change(.outputMode, payload: [(single ? 1 : 0) | (high ? (single ? 64 : 32) : 0)]) { $0.outputMode = mode }
    }
    func setTrim(left: Double, right: Double) {
        guard left.isFinite, right.isFinite else { return }
        let left = min(0, max(-6, left)), right = min(0, max(-6, right))
        change(.trim, payload: Wire.volume(left) + Wire.volume(right)) { $0.leftTrim = left; $0.rightTrim = right }
    }
    func setJitter(usb: Bool, bluetooth: Bool) {
        change(.jitter, payload: [(usb ? 1 : 0) | (bluetooth ? 2 : 0)]) { $0.jitterUSB = usb; $0.jitterBluetooth = bluetooth }
    }
    func setCodecs(aac: Bool, aptx: Bool, hd: Bool) {
        change(.codecs, payload: [UInt8(1 | (aac ? 2 : 0) | (aptx ? 4 : 0) | (hd ? 8 : 0))]) { $0.aac = aac; $0.aptx = aptx; $0.aptxHD = hd }
    }
    func setMic(ambient: Bool, preamp: Bool, gain: Int) {
        let gain = min(22, max(0, gain))
        change(ambient ? .ambientMic : .mic, payload: [UInt8((preamp ? 128 : 0) | gain)]) {
            if ambient { $0.ambientPreamp = preamp; $0.ambientGain = gain }
            else { $0.micPreamp = preamp; $0.micGain = gain }
        }
    }
    func applyPreset(_ preset: EQPreset) {
        guard available(.eq, .allGains), let preset = try? preset.validated() else { return }
        change(.allGains, payload: ([preset.preamp] + preset.bands).map(Wire.gain)) { $0.preamp = preset.preamp; $0.bands = preset.bands }
        if state.supportsQ { setQ(preset.q) }
        if state.supportsHeadroom { setHeadroom(preset.headroom, compensation: preset.analogCompensation) }
        presetName = preset.name
    }
    func savePreset(name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !name.isEmpty, available(.eq) else { return }
        let preset = EQPreset(name: name, preamp: state.preamp, bands: state.bands, q: state.q, headroom: state.headroom, analogCompensation: state.analogCompensation)
        guard (try? preset.validated()) != nil else { message = "Refresh device settings before saving a preset."; return }
        presets.append(preset); persistPresets(); presetName = name
    }
    func deletePreset(_ id: UUID) { presets.removeAll { $0.id == id }; persistPresets() }
    private func persistPresets() {
        if let data = try? JSONEncoder().encode(PresetFile(presets: presets)) { defaults.set(data, forKey: "presets") }
    }
    func importPresets() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json, .xml]; panel.allowsMultipleSelection = false
        panel.message = "Import EarStudio presets or an exported Android SharedPreferences XML file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw PresetError.tooLarge }
            let imported = try PresetFile.decode(Data(contentsOf: url))
            presets += imported.map { var p = $0; p.id = UUID(); return p }
            persistPresets()
            message = "Imported \(imported.count) preset\(imported.count == 1 ? "" : "s"). Select a preset to apply it."
            if url.pathExtension.lowercased() == "xml" { message! += " Android imports use narrow Q and default headroom; those values are not stored in the Android preset slots." }
        } catch { message = error.localizedDescription }
    }
    func exportPresets() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "EarStudio Presets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let current = EQPreset(name: presetName, preamp: state.preamp, bands: state.bands, q: state.q, headroom: state.headroom, analogCompensation: state.analogCompensation)
            let content = presets.isEmpty && available(.eq) ? [current] : presets
            guard !content.isEmpty else { throw PresetError.noPresets }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(PresetFile(presets: content)).write(to: url, options: .atomic)
        } catch { message = error.localizedDescription }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "EarStudio Diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = "EarStudio Companion \(AppMetadata.version) (\(AppMetadata.build))\nFirmware: \(state.firmware ?? "unknown")\n\(logs.map { "\($0.date.ISO8601Format()) \($0.text)" }.joined(separator: "\n"))\n"
        do { try content.write(to: url, atomically: true, encoding: .utf8) } catch { message = error.localizedDescription }
    }
    private func commandName(_ command: DeviceCommand) -> String { String(describing: command) }
    private func log(_ text: String) {
        logs.append(LogEntry(text: text)); if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }
}
