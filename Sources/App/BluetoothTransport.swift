import Foundation
import IOBluetooth

struct DiscoveredDevice: Identifiable {
    let device: IOBluetoothDevice
    var id: String { device.addressString ?? "" }
    var name: String { device.name ?? "EarStudio" }
    var paired: Bool { device.isPaired() }
}

/// Apple delivers IOBluetooth callbacks on the application's main run loop.
/// One transport instance belongs to one connection attempt; old callbacks are
/// ignored after close so they cannot affect a newly selected device.
final class BluetoothTransport: NSObject, IOBluetoothDeviceInquiryDelegate, IOBluetoothDeviceAsyncCallbacks, IOBluetoothRFCOMMChannelDelegate {
    var onDevices: (([DiscoveredDevice]) -> Void)?
    var onScanFinished: (() -> Void)?
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((String) -> Void)?
    private var inquiry: IOBluetoothDeviceInquiry?
    private var devices: [String: DiscoveredDevice] = [:]
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var closed = false
    private var openingTimer: Timer?
    // writeAsync requires storage to remain alive until write completion.
    private var writeBuffers: [UInt: UnsafeMutableRawPointer] = [:]
    private var nextWrite: UInt = 1

    func loadPaired() {
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] { add(device) }
        publishDevices()
    }
    func scan() {
        loadPaired()
        guard inquiry == nil else { return }
        let scan = IOBluetoothDeviceInquiry(delegate: self)
        scan?.inquiryLength = 8
        scan?.updateNewDeviceNames = true
        inquiry = scan
        guard let scan, scan.start() == kIOReturnSuccess else {
            inquiry = nil
            onError?("Bluetooth discovery could not start. Turn on Bluetooth and allow EarStudio in System Settings → Privacy & Security → Bluetooth.")
            onScanFinished?(); return
        }
    }
    func stopScan() { _ = inquiry?.stop(); inquiry = nil }
    private func add(_ device: IOBluetoothDevice) {
        let name = (device.name ?? "").lowercased()
        guard name.contains("earstudio") || name.contains("es100") else { return }
        let found = DiscoveredDevice(device: device)
        if !found.id.isEmpty { devices[found.id] = found }
    }
    private func publishDevices() { onDevices?(devices.values.sorted { $0.name < $1.name }) }
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let device else { return }; add(device); publishDevices()
    }
    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        guard let device else { return }; add(device); publishDevices()
    }
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        inquiry = nil; publishDevices(); onScanFinished?()
        if error != kIOReturnSuccess && !aborted { onError?("Bluetooth search ended with error \(error).") }
    }
    func connect(_ target: IOBluetoothDevice) {
        stopScan(); closed = false; device = target
        openingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.fail("Connection timed out. Keep ES100 nearby, pair it in macOS Bluetooth settings, and close other EarStudio control apps.")
        }
        let status = target.performSDPQuery(self)
        if status != kIOReturnSuccess { fail("Could not query the device's Bluetooth services (\(status)).") }
    }
    func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard !closed, device == self.device else { return }
        guard status == kIOReturnSuccess else { fail("Service discovery failed (\(status)). Try pairing ES100 in Bluetooth settings first."); return }
        let spp = IOBluetoothSDPUUID(uuid16: 0x1101)!
        let gaiaBytes: [UInt8] = [0, 0, 0x11, 7, 0xD1, 2, 0x11, 0xE1, 0x9B, 0x23, 0, 2, 0x5B, 0, 0xA5, 0xA5]
        let gaia = gaiaBytes.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        for uuid in [spp, gaia] {
            guard let service = device.getServiceRecord(for: uuid) else { continue }
            var channelID: BluetoothRFCOMMChannelID = 0
            guard service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess, channelID > 0 else { continue }
            let result = device.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: self)
            if result != kIOReturnSuccess { fail("The control channel could not open (\(result)).") }
            return
        }
        fail("This device did not advertise the EarStudio serial control service. Try reconnecting after closing the phone app.")
    }
    // Required by the shared async callback protocol; this transport uses SDP
    // and RFCOMM completion callbacks rather than opening a baseband link itself.
    func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard !closed, rfcommChannel == channel else { return }
        openingTimer?.invalidate(); openingTimer = nil
        guard error == kIOReturnSuccess else { fail("Bluetooth channel failed to open (\(error))."); return }
        onOpen?()
    }
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard !closed, rfcommChannel == channel, let dataPointer, dataLength > 0 else { return }
        onData?(Data(bytes: dataPointer, count: dataLength))
    }
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard !closed, rfcommChannel == channel else { return }
        close(); onClose?()
    }
    func send(_ data: Data) -> Bool {
        guard !closed, let channel, channel.isOpen() else { return false }
        let mtu = Int(channel.getMTU())
        guard mtu > 0 else { return false }
        var offset = 0
        while offset < data.count {
            let count = min(mtu, data.count - offset)
            let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 1)
            data.withUnsafeBytes { raw in pointer.copyMemory(from: raw.baseAddress!.advanced(by: offset), byteCount: count) }
            let token = nextWrite; nextWrite += 1
            writeBuffers[token] = pointer
            let result = channel.writeAsync(pointer, length: UInt16(count), refcon: UnsafeMutableRawPointer(bitPattern: token))
            if result != kIOReturnSuccess {
                writeBuffers.removeValue(forKey: token)?.deallocate()
                fail("Bluetooth write failed (\(result))."); return false
            }
            offset += count
        }
        return true
    }
    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        if let refcon { writeBuffers.removeValue(forKey: UInt(bitPattern: refcon))?.deallocate() }
        if !closed, error != kIOReturnSuccess { fail("Bluetooth transmission failed (\(error)).") }
    }
    func close() {
        closed = true; openingTimer?.invalidate(); openingTimer = nil; stopScan()
        if let channel { _ = channel.close(); _ = channel.setDelegate(nil) }
        channel = nil; device = nil
        // The channel has closed and no longer owns these pending buffers.
        for buffer in writeBuffers.values { buffer.deallocate() }
        writeBuffers.removeAll()
    }
    private func fail(_ message: String) { close(); onError?(message) }
    deinit {
        openingTimer?.invalidate()
        for buffer in writeBuffers.values { buffer.deallocate() }
    }
}
