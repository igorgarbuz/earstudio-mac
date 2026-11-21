import Foundation
import Combine
import CoreBluetooth
import EarStudioSession

struct IOSDevice: Identifiable, Equatable {
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
    static let compatibilityNotice = "The iPhone Bluetooth connection is experimental and still needs testing with a physical ES100."
    private var central: CBCentralManager?
    private var scanRequested = false
    private var scanDeadline: Timer?
    // Core Bluetooth expects clients to retain discovered peripherals. Keep them
    // alive while the user chooses; the transport retrieves its own central's
    // instance and retains it for the complete connection lifetime.
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var subscriptions = Set<AnyCancellable>()

    init(demo: Bool = false) {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let defaults: UserDefaults
        if isUITesting {
            let suite = "EarStudioCompanion.iOS.UITests"
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
        } else if demo {
            defaults = UserDefaults(suiteName: "EarStudioCompanion.iOS.Demo")!
        } else { defaults = .standard }
        let keys = IOSDeviceKeyStore()
        session = DeviceSession(demo: demo, defaults: defaults,
            saveDeviceKey: { key, id in isUITesting ? true : keys.save(key, for: id) },
            readDeviceKey: { id in isUITesting ? 0 : keys.read(id) },
            forgetDeviceKey: { id in isUITesting ? true : keys.forget(id) })
        super.init()
        session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    func startDiscovery() {
        guard !session.isBusy, session.phase != .connected else { return }
        stopDiscovery()
        devices = []; discoveredPeripherals.removeAll(); scanRequested = true; scanning = true
        // Bound the whole request, including an OS state stuck at unknown/resetting
        // or a permission prompt that the user leaves unanswered.
        scanDeadline = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self, self.scanRequested else { return }
            let wasReady = self.central?.state == .poweredOn
            self.stopDiscovery()
            if !wasReady {
                self.connectionMessage = "Bluetooth did not become ready. Check Bluetooth permission and power in iPhone Settings, then scan again."
            } else {
                self.connectionMessage = self.devices.isEmpty
                    ? "No EarStudio found. Turn it on, keep it nearby, and close other controller apps. Audio pairing alone does not open its settings channel."
                    : "Choose your EarStudio to connect."
            }
        }
        connectionMessage = "Looking for nearby EarStudio devices…"
        if let central {
            updateDiscovery(for: central)
        } else {
            // Creating the central can request permission, so only do it after
            // the user chooses Scan. Demo and initial launch need no Bluetooth.
            central = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    func stopDiscovery() {
        scanRequested = false; scanning = false
        scanDeadline?.invalidate(); scanDeadline = nil
        central?.stopScan()
    }

    func connect(_ device: IOSDevice) {
        guard !session.isBusy else { return }
        stopDiscovery()
        connectionMessage = Self.compatibilityNotice
        session.connect(DeviceConnection(id: device.id.uuidString, name: device.name,
            makeTransport: { IOSBLETransport(identifier: device.id) }))
    }

    func disconnect() {
        stopDiscovery()
        session.disconnect()
        connectionMessage = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) { updateDiscovery(for: central) }

    private func updateDiscovery(for central: CBCentralManager) {
        guard scanRequested else { return }
        switch central.state {
        case .poweredOn:
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
            connectionMessage = "Allow Bluetooth access for EarStudio in iPhone Settings, then scan again."
        case .poweredOff:
            stopDiscovery()
            connectionMessage = "Turn on Bluetooth in iPhone Settings, then scan again."
        case .unsupported:
            stopDiscovery()
            connectionMessage = "Bluetooth Low Energy is unavailable here."
        @unknown default:
            stopDiscovery()
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
        let device = IOSDevice(id: peripheral.identifier, name: name, signal: signal)
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
        devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func isEarStudioName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("earstudio") || normalized.contains("es100")
    }
}
