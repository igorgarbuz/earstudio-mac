import Foundation
import CoreBluetooth
import EarStudioSession

/// One Core Bluetooth central per attempt isolates callbacks from retired links.
/// This supports the documented GAIA BLE v1 profile only. Actual ES100 firmware
/// compatibility must still be established with a physical device.
final class IOSBLETransport: NSObject, SessionTransport, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((TransportFailure) -> Void)?
    var onDiagnostic: ((String) -> Void)?

    private let identifier: UUID
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private var response: CBCharacteristic?
    private var deadline: Timer?
    private var closeDeadline: Timer?
    private var writeDeadline: Timer?
    private var closeCompletions: [() -> Void] = []
    private var opened = false
    private var closing = false
    private var closed = false
    private var writes: [Data] = []
    private var writePending = false

    init(identifier: UUID) { self.identifier = identifier }

    func open() {
        guard central == nil, !closed, !closing else { return }
        deadline = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.fail("EarStudio did not open its Bluetooth settings channel within 20 seconds.")
        }
        central = CBCentralManager(delegate: self, queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !closed else { return }
        if closing { if central.state != .poweredOn { finishClose() }; return }
        guard central.state == .poweredOn else {
            switch central.state {
            case .unknown: return
            case .resetting:
                // Once acquired, CBPeripheral objects and service handles cannot
                // be assumed valid across a controller reset. Start fresh later.
                if peripheral != nil { fail("Bluetooth restarted. Reconnect to refresh the EarStudio settings channel.") }
                return
            case .unauthorized: fail("Allow Bluetooth access for ES100 Control in iPhone Settings.")
            case .poweredOff: fail("Turn on Bluetooth in iPhone Settings, then reconnect.")
            case .unsupported: fail("Bluetooth Low Energy is unavailable on this device.")
            default: fail("Bluetooth is unavailable. Try connecting again.")
            }
            return
        }
        guard peripheral == nil else { return }
        guard let target = central.retrievePeripherals(withIdentifiers: [identifier]).first else {
            fail("This device is no longer available. Scan for EarStudio again.")
            return
        }
        peripheral = target
        target.delegate = self
        central.connect(target)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard accepts(peripheral) else {
            if closing { central.cancelPeripheralConnection(peripheral) }
            return
        }
        onDiagnostic?("Bluetooth LE connected. Checking the GAIA service.")
        peripheral.discoverServices([CBUUID(string: GAIABLECodec.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        if closing { finishClose(); return }
        fail("The iPhone could not connect to EarStudio. Check its power and close other controllers.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        if closing { finishClose(); return }
        guard !closed else { return }
        opened = false
        onClose?()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard accepts(peripheral) else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: GAIABLECodec.serviceUUID) }) else {
            fail("This EarStudio did not expose the supported GAIA Bluetooth LE service. Its iPhone control connection needs further compatibility testing.")
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: GAIABLECodec.commandUUID),
                                            CBUUID(string: GAIABLECodec.responseUUID),
                                            CBUUID(string: GAIABLECodec.dataUUID)], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard accepts(peripheral) else { return }
        let values = service.characteristics ?? []
        guard error == nil,
              let command = values.first(where: { $0.uuid == CBUUID(string: GAIABLECodec.commandUUID) }),
              let response = values.first(where: { $0.uuid == CBUUID(string: GAIABLECodec.responseUUID) }),
              let data = values.first(where: { $0.uuid == CBUUID(string: GAIABLECodec.dataUUID) }),
              command.properties.contains(.write), data.properties.contains(.read),
              response.properties.contains(.notify) || response.properties.contains(.indicate) else {
            fail("The device's Bluetooth LE characteristics do not match the supported GAIA profile. No device settings were sent.")
            return
        }
        self.command = command; self.response = response
        peripheral.setNotifyValue(true, for: response)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard accepts(peripheral), characteristic === response else { return }
        guard error == nil, characteristic.isNotifying else {
            fail("EarStudio could not enable settings notifications. Disconnect other controller apps and try again.")
            return
        }
        guard !opened else { return }
        opened = true; deadline?.invalidate(); deadline = nil
        onDiagnostic?("GAIA BLE response notifications enabled.")
        onOpen?()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard accepts(peripheral), opened, characteristic === response else { return }
        guard error == nil, let data = characteristic.value,
              let streamFrame = GAIABLECodec.decode(characteristicValue: data) else {
            fail("EarStudio returned an unsupported Bluetooth LE response. Disconnect and export diagnostics before retrying.")
            return
        }
        onData?(streamFrame)
    }

    func send(_ data: Data) -> Bool {
        guard !closed, !closing, opened, let peripheral, let command,
              central?.state == .poweredOn, peripheral.state == .connected,
              let value = GAIABLECodec.encode(streamFrame: data),
              value.count <= peripheral.maximumWriteValueLength(for: .withResponse),
              writes.count < 32 else { return false }
        // ATT write completion is not a firmware acknowledgement. The shared
        // session still requires its actual setting readback before confirming.
        writes.append(value)
        sendNext(peripheral, command)
        return true
    }

    private func sendNext(_ peripheral: CBPeripheral, _ command: CBCharacteristic) {
        guard !writePending, !writes.isEmpty else { return }
        writePending = true
        writeDeadline = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.fail("The Bluetooth write did not finish. Its outcome is uncertain; reconnect to read the current device settings.")
        }
        peripheral.writeValue(writes.removeFirst(), for: command, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard accepts(peripheral), characteristic === command else { return }
        writePending = false
        writeDeadline?.invalidate(); writeDeadline = nil
        guard error == nil else {
            fail("A Bluetooth settings write failed. The change may have reached EarStudio; reconnect to read its current settings.")
            return
        }
        if let command { sendNext(peripheral, command) }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard accepts(peripheral) else { return }
        if invalidatedServices.contains(where: { $0.uuid == CBUUID(string: GAIABLECodec.serviceUUID) }) {
            fail("EarStudio changed its Bluetooth services. Reconnect to refresh the settings connection.")
        }
    }

    func close(completion: @escaping () -> Void) {
        guard !closed else { completion(); return }
        closeCompletions.append(completion)
        guard !closing else { return }
        closing = true; opened = false
        deadline?.invalidate(); deadline = nil; writeDeadline?.invalidate(); writeDeadline = nil; writes.removeAll()
        guard let central, let peripheral, central.state == .poweredOn,
              peripheral.state != .disconnected else { finishClose(); return }
        central.cancelPeripheralConnection(peripheral)
        // Release this manager if the OS never delivers cancellation. Its native
        // connection ownership is dropped before a subsequent attempt begins.
        closeDeadline = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.finishClose() }
    }

    private func finishClose() {
        guard !closed else { return }
        closed = true; closing = false; opened = false
        deadline?.invalidate(); closeDeadline?.invalidate(); writeDeadline?.invalidate()
        peripheral?.delegate = nil; central?.delegate = nil
        peripheral = nil; central = nil; command = nil; response = nil
        writes.removeAll(); writePending = false
        let callbacks = closeCompletions; closeCompletions.removeAll()
        callbacks.forEach { $0() }
    }
    private func accepts(_ value: CBPeripheral) -> Bool { !closed && !closing && value === peripheral }
    private func fail(_ message: String) {
        guard !closing, !closed else { return }
        deadline?.invalidate(); opened = false
        onError?(TransportFailure(message: message))
    }
}
