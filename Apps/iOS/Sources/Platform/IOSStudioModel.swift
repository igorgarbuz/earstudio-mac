import Foundation
import Combine
import CoreBluetooth
import EarStudioSession

struct IOSDevice: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    var signal: Int?
}

/// The iPhone owns discovery and authorization storage. All device setting
/// behavior stays in the shared session; no audio routing is changed here.
final class IOSStudioModel: NSObject, ObservableObject, CBCentralManagerDelegate {
    let session: DeviceSession
    @Published private(set) var devices: [IOSDevice] = []
    @Published private(set) var scanning = false
    @Published var connectionMessage: String?
    @Published var showDevicePicker = false
    @Published private(set) var rememberedDevice: IOSDevice?
    private let discoverDevices: (() -> Void)?
    private let selectionDelay: TimeInterval
    private let preferences: UserDefaults
    private let makeTransport: (UUID) -> SessionTransport
    private var connectingDevice: IOSDevice?
    private var automaticSelection = false
    private var foregroundHandled = false
    private var autoConnectSuppressed = false
    private var selectionWindow: Timer?
    private let rememberedDeviceKey = "lastConnectedEarStudio"
    static let compatibilityNotice = "Turn on your EarStudio and keep it nearby. Close other controller apps before connecting."
    private var central: CBCentralManager?
    private var scanRequested = false
    private var scanDeadline: Timer?
    // Core Bluetooth expects clients to retain discovered peripherals. Keep them
    // alive while the user chooses; the transport retrieves its own central's
    // instance and retains it for the complete connection lifetime.
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var subscriptions = Set<AnyCancellable>()

    init(demo: Bool = false, defaults injectedDefaults: UserDefaults? = nil,
         makeTransport: @escaping (UUID) -> SessionTransport = { IOSBLETransport(identifier: $0) },
         discoverDevices: (() -> Void)? = nil, selectionDelay: TimeInterval = 3) {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let defaults: UserDefaults
        if let injectedDefaults {
            defaults = injectedDefaults
        } else if isUITesting {
            let suite = "EarStudioCompanion.iOS.UITests"
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
        } else if demo {
            defaults = UserDefaults(suiteName: "EarStudioCompanion.iOS.Demo")!
        } else { defaults = .standard }
        self.discoverDevices = discoverDevices
        self.selectionDelay = selectionDelay
        preferences = defaults
        self.makeTransport = makeTransport
        if let data = defaults.data(forKey: "lastConnectedEarStudio") {
            rememberedDevice = try? JSONDecoder().decode(IOSDevice.self, from: data)
        }
        let keys = IOSDeviceKeyStore()
        session = DeviceSession(demo: demo, defaults: defaults,
            saveDeviceKey: { key, id in isUITesting ? true : keys.save(key, for: id) },
            readDeviceKey: { id in isUITesting ? 0 : keys.read(id) },
            forgetDeviceKey: { id in isUITesting ? true : keys.forget(id) })
        super.init()
        session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        session.$phase.sink { [weak self] phase in
            guard phase == .connected, let self, let device = self.connectingDevice else { return }
            self.rememberedDevice = device
            if let data = try? JSONEncoder().encode(device) {
                self.preferences.set(data, forKey: self.rememberedDeviceKey)
            }
        }.store(in: &subscriptions)
    }

    func becameActive() {
        guard !foregroundHandled else { return }
        foregroundHandled = true
        guard !session.isDemo, !autoConnectSuppressed, !showDevicePicker,
              rememberedDevice != nil else { return }
        requestConnection()
    }

    func enteredBackground() {
        foregroundHandled = false
        stopDiscovery()
        // Cancel pending writes before suspension; reconnect with fresh readback.
        if !session.isDemo { session.disconnect() }
        connectionMessage = nil
    }

    func requestConnection() {
        guard !session.isBusy, session.phase != .connected, !scanning else { return }
        if let rememberedDevice { connect(rememberedDevice) }
        else { startDiscovery(automaticallyConnect: true) }
    }

    func changeDevice() {
        guard !session.isBusy else { return }
        showDevicePicker = true
        startDiscovery()
    }

    func cancelConnection() {
        autoConnectSuppressed = true
        stopDiscovery()
        if session.isBusy { session.cancelConfirmation() }
        connectionMessage = nil
    }

    func startDiscovery(automaticallyConnect: Bool = false) {
        guard !session.isBusy else { return }
        stopDiscovery()
        automaticSelection = automaticallyConnect
        devices = []; discoveredPeripherals.removeAll(); scanRequested = true; scanning = true
        // Bound the whole request, including an OS state stuck at unknown/resetting
        // or a permission prompt that the user leaves unanswered.
        scanDeadline = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.finishDiscovery(bluetoothReady: self.central?.state == .poweredOn)
        }
        connectionMessage = "Looking for nearby EarStudio devices…"
        if let discoverDevices {
            discoverDevices()
        } else if let central {
            updateDiscovery(for: central)
        } else {
            // Creating the central can request permission, so only do it after
            // the user chooses Scan. Demo and initial launch need no Bluetooth.
            central = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    func finishDiscovery(bluetoothReady: Bool) {
        guard scanRequested else { return }
        // A late first result still gets the full window to reveal another DAC.
        if bluetoothReady, automaticSelection, devices.count == 1, selectionWindow != nil { return }
        stopDiscovery()
        showDevicePicker = true
        if !bluetoothReady {
            connectionMessage = "Bluetooth did not become ready. Check Bluetooth permission and power in iPhone Settings, then scan again."
        } else {
            connectionMessage = devices.isEmpty
                ? "No EarStudio found. Turn it on, keep it nearby, and close other controller apps."
                : nil
        }
    }

    func stopDiscovery() {
        scanRequested = false; scanning = false
        automaticSelection = false
        selectionWindow?.invalidate(); selectionWindow = nil
        scanDeadline?.invalidate(); scanDeadline = nil
        central?.stopScan()
    }

    func connect(_ device: IOSDevice) {
        guard !session.isBusy else { return }
        stopDiscovery()
        showDevicePicker = false
        connectionMessage = nil
        autoConnectSuppressed = false
        connectingDevice = device
        let makeTransport = self.makeTransport
        session.connect(DeviceConnection(id: device.id.uuidString, name: device.name,
            makeTransport: { makeTransport(device.id) }))
    }

    func disconnect() {
        autoConnectSuppressed = true
        stopDiscovery()
        session.disconnect()
        connectionMessage = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) { updateDiscovery(for: central) }

    private func updateDiscovery(for central: CBCentralManager) {
        guard scanRequested else { return }
        switch central.state {
        case .poweredOn:
            connectionMessage = "Looking for nearby EarStudio devices…"
            guard !central.isScanning else { return }
            for device in central.retrieveConnectedPeripherals(withServices: [CBUUID(string: GAIABLECodec.serviceUUID)]) {
                add(device, advertisedName: nil, signal: nil)
            }
            // ES100 may omit its service UUID from advertisements. Restrict
            // display by product name and validate the actual profile on connect.
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        case .unknown, .resetting:
            connectionMessage = "Waiting for Bluetooth…"
        case .unauthorized:
            stopDiscovery()
            showDevicePicker = true
            connectionMessage = "Allow Bluetooth access for ES100 Control in iPhone Settings, then scan again."
        case .poweredOff:
            stopDiscovery()
            showDevicePicker = true
            connectionMessage = "Turn on Bluetooth in iPhone Settings, then scan again."
        case .unsupported:
            stopDiscovery()
            showDevicePicker = true
            connectionMessage = "Bluetooth Low Energy is unavailable here."
        @unknown default:
            stopDiscovery()
            showDevicePicker = true
            connectionMessage = "Bluetooth is unavailable. Try scanning again."
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanRequested else { return }
        add(peripheral, advertisedName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            signal: RSSI.intValue == 127 ? nil : RSSI.intValue)
    }

    private func add(_ peripheral: CBPeripheral, advertisedName: String?, signal: Int?) {
        let name = advertisedName ?? peripheral.name ?? ""
        guard Self.isEarStudioName(name) else { return }
        discoveredPeripherals[peripheral.identifier] = peripheral
        recordDiscoveredDevice(IOSDevice(id: peripheral.identifier, name: name, signal: signal))
    }

    func recordDiscoveredDevice(_ device: IOSDevice) {
        guard scanRequested, Self.isEarStudioName(device.name) else { return }
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
        devices.sort {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
        considerAutomaticSelection()
    }

    // Called after discovery updates; never select the first advertisement immediately.
    private func considerAutomaticSelection() {
        guard automaticSelection, scanning else { return }
        if devices.count > 1 {
            automaticSelection = false
            selectionWindow?.invalidate(); selectionWindow = nil
            showDevicePicker = true
        } else if devices.count == 1, selectionWindow == nil {
            selectionWindow = Timer.scheduledTimer(withTimeInterval: selectionDelay, repeats: false) { [weak self] _ in
                guard let self, self.automaticSelection, self.scanning,
                      self.devices.count == 1, let device = self.devices.first else { return }
                self.connect(device)
            }
        }
    }

    static func isEarStudioName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("earstudio") || normalized.contains("es100")
    }
}
