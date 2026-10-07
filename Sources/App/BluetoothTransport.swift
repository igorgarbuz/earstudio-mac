import Foundation
import AppKit
import Darwin
import IOBluetooth

/// macOS/ES100 support one owner of the serial control link. flock also releases
/// ownership when a process crashes, unlike a persisted "connected" preference.
final class ControlChannelLease {
    enum Failure: Equatable { case occupied, unavailable(Int32) }
    private(set) var failure: Failure?
    private var descriptor: Int32 = -1
    func acquire(at url: URL) -> Bool {
        failure = nil
        guard descriptor == -1 else { return true }
        let fd = Darwin.open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { failure = .unavailable(errno); return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            failure = code == EWOULDBLOCK ? .occupied : .unavailable(code)
            Darwin.close(fd); return false
        }
        descriptor = fd
        return true
    }
    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN); Darwin.close(descriptor); descriptor = -1
    }
    deinit { release() }
}

struct DiscoveredDevice: Identifiable {
    let device: IOBluetoothDevice
    var id: String { device.addressString ?? "" }
    var name: String { device.name ?? "EarStudio" }
    var paired: Bool { device.isPaired() }
}

protocol ControlTransport: AnyObject {
    var onOpen: (() -> Void)? { get set }
    var onData: ((Data) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onDiagnostic: ((String) -> Void)? { get set }
    func connect(_ target: IOBluetoothDevice)
    func send(_ data: Data) -> Bool
    func close(completion: @escaping () -> Void)
}

/// Apple delivers IOBluetooth callbacks on the application's main run loop.
/// One transport instance belongs to one connection attempt; old callbacks are
/// ignored after close so they cannot affect a newly selected device.
final class BluetoothTransport: NSObject, ControlTransport, IOBluetoothDeviceInquiryDelegate, IOBluetoothDeviceAsyncCallbacks, IOBluetoothRFCOMMChannelDelegate {
    var onDevices: (([DiscoveredDevice]) -> Void)?
    var onScanFinished: (() -> Void)?
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((String) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    private var inquiry: IOBluetoothDeviceInquiry?
    private var devices: [String: DiscoveredDevice] = [:]
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var closed = false
    private var openingTimer: Timer?
    private var openingRFCOMM = false
    private var closing = false
    private var closeNotification: IOBluetoothUserNotification?
    private var closeCompletions: [() -> Void] = []
    private let lease = ControlChannelLease()
    // writeAsync requires storage to remain alive until write completion.
    private var writeBuffers: [UInt: UnsafeMutableRawPointer] = [:]
    private static var nextWrite: UInt = 1
    private var retiredChannel: IOBluetoothRFCOMMChannel?
    private static var writeOwners: [UInt: BluetoothTransport] = [:]
    private final class WeakOwner {
        weak var value: BluetoothTransport?
        init(_ value: BluetoothTransport) { self.value = value }
    }
    private static var channelOwners: [ObjectIdentifier: WeakOwner] = [:]

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
        // Older copies do not implement the lease, so identify those too.
        if target.addressString != nil {
            if let bundleID = Bundle.main.bundleIdentifier,
               NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                fail("Another copy of EarStudio Companion is running. Quit the other copy, then connect again."); return
            }
            let lock = FileManager.default.temporaryDirectory.appendingPathComponent("earstudio-companion-control.lock")
            guard lease.acquire(at: lock) else {
                fail("Another EarStudio Companion process owns the control channel, or its lock could not be opened. Quit the other copy and try again."); return
            }
        }
        onDiagnostic?("Discovering Bluetooth services. Mac link: \(target.isConnected() ? "connected" : "disconnected").")
        openingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.fail(self.openingRFCOMM
                ? "The ES100 control channel did not open. Bluetooth audio can still be connected. Use Reconnect Bluetooth below to reset the device connection."
                : "Bluetooth service discovery timed out. Keep ES100 nearby and check its connection in macOS Bluetooth settings.")
        }
        let status = target.performSDPQuery(self, uuids: serviceUUIDs)
        if status != kIOReturnSuccess { fail("Could not query the device's Bluetooth services (\(status)).") }
    }
    func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard !closed, !openingRFCOMM, channel == nil, device == self.device else { return }
        onDiagnostic?("Bluetooth service discovery completed (\(status)).")
        guard status == kIOReturnSuccess else { fail("Service discovery failed (\(status)). Try pairing ES100 in Bluetooth settings first."); return }
        onDiagnostic?("Service records updated: \(device.getLastServicesUpdate()?.description ?? "unknown").")
        for uuid in serviceUUIDs {
            guard let service = device.getServiceRecord(for: uuid) else { continue }
            var channelID: BluetoothRFCOMMChannelID = 0
            guard service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess, channelID > 0 else { continue }
            openChannel(channelID, on: device)
            return
        }
        fail("This device did not advertise the EarStudio serial control service. Try reconnecting after closing the phone app.")
    }
    private var serviceUUIDs: [IOBluetoothSDPUUID] {
        let spp = IOBluetoothSDPUUID(uuid16: 0x1101)!
        let gaiaBytes: [UInt8] = [0, 0, 0x11, 7, 0xD1, 2, 0x11, 0xE1, 0x9B, 0x23, 0, 2, 0x5B, 0, 0xA5, 0xA5]
        let gaia = gaiaBytes.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        return [spp, gaia].compactMap { $0 }
    }
    private func openChannel(_ channelID: BluetoothRFCOMMChannelID, on device: IOBluetoothDevice) {
        openingRFCOMM = true
        onDiagnostic?("Opening RFCOMM channel \(channelID).")
        // Do not pass a stored property inout while a delegate callback may run.
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
        channel = opened
        onDiagnostic?("RFCOMM open request returned \(result); channel object: \(opened == nil ? "missing" : "present"); already open: \(opened?.isOpen() == true).")
        guard result == kIOReturnSuccess, let opened else {
            fail("The control channel could not open (\(result)); macOS did not return a usable channel."); return
        }
        Self.channelOwners[ObjectIdentifier(opened)] = WeakOwner(self)
        let delegateStatus = opened.setDelegate(self)
        guard delegateStatus == kIOReturnSuccess else {
            fail("The control channel could not register its listener (\(delegateStatus))."); return
        }
        // Apple's API may return an existing open channel. In that case it
        // need not issue a new open callback; waiting for one causes a false
        // timeout after relaunch. Reattach the listener before authentication.
        if opened.isOpen() {
            DispatchQueue.main.async { [weak self] in self?.completeOpen(opened, status: kIOReturnSuccess) }
        }
    }
    // Required by the shared async callback protocol; this transport uses SDP
    // and RFCOMM completion callbacks rather than opening a baseband link itself.
    func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        // A completion can arrive before openRFCOMMChannelAsync assigns its out
        // parameter. Process it on the next main-loop turn, after that assignment.
        DispatchQueue.main.async { [weak self] in
            self?.completeOpen(rfcommChannel, status: error)
        }
    }
    private func completeOpen(_ rfcommChannel: IOBluetoothRFCOMMChannel?, status error: IOReturn) {
        onDiagnostic?("RFCOMM open completion: \(error); channel object: \(rfcommChannel == nil ? "missing" : "present").")
        if closed {
            if error == kIOReturnSuccess, let rfcommChannel {
                onDiagnostic?("Closing a channel that opened after cancellation.")
                _ = rfcommChannel.close()
            }
            return
        }
        guard openingRFCOMM else { return }
        // Failure callbacks may not carry a usable channel. They still finish
        // the current opening attempt instead of being lost to the timeout.
        guard error != kIOReturnSuccess || (rfcommChannel != nil && rfcommChannel == channel) else { return }
        openingRFCOMM = false
        openingTimer?.invalidate(); openingTimer = nil
        guard error == kIOReturnSuccess else {
            fail("The ES100 control channel could not reopen (Bluetooth error \(error)). Use Reconnect Bluetooth below to reset the device connection.")
            return
        }
        onOpen?()
    }
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard !closed, rfcommChannel == channel, let dataPointer, dataLength > 0 else { return }
        onData?(Data(bytes: dataPointer, count: dataLength))
    }
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel != nil, rfcommChannel == channel else { return }
        onDiagnostic?("RFCOMM channel closed.")
        if closing { finishClose(); return }
        guard !closed else { return }
        closed = true; openingTimer?.invalidate(); openingTimer = nil
        finishClose(); onClose?()
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
            let token = Self.nextWrite; Self.nextWrite += 1
            writeBuffers[token] = pointer
            Self.writeOwners[token] = self
            let result = channel.writeAsync(pointer, length: UInt16(count), refcon: UnsafeMutableRawPointer(bitPattern: token))
            if result != kIOReturnSuccess {
                writeBuffers.removeValue(forKey: token)?.deallocate()
                Self.writeOwners.removeValue(forKey: token)
                fail("Bluetooth write failed (\(result))."); return false
            }
            offset += count
        }
        return true
    }
    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        guard let refcon, let owner = Self.writeOwners.removeValue(forKey: UInt(bitPattern: refcon)) else { return }
        // macOS may reuse a channel and deliver an old completion to its new
        // delegate. Tokens are process-wide; free only the original write's data.
        owner.finishWrite(UInt(bitPattern: refcon), status: error)
    }
    private func finishWrite(_ token: UInt, status error: IOReturn) {
        writeBuffers.removeValue(forKey: token)?.deallocate()
        if writeBuffers.isEmpty, let retiredChannel {
            detachIfOwned(retiredChannel); self.retiredChannel = nil
        }
        if !closed, error != kIOReturnSuccess { fail("Bluetooth transmission failed (\(error)).") }
    }
    func close(completion: @escaping () -> Void = {}) {
        if closing { closeCompletions.append(completion); return }
        if closed { completion(); return }
        closeCompletions.append(completion)
        closing = true; closed = true; openingRFCOMM = false
        openingTimer?.invalidate(); openingTimer = nil; stopScan()
        guard let channel else { finishClose(); return }
        closeNotification = channel.register(forChannelCloseNotification: self, selector: #selector(channelDidClose(_:channel:)))
        let result = channel.close()
        onDiagnostic?("RFCOMM close requested (\(result)).")
        if result != kIOReturnSuccess { finishClose(); return }
        // Retain the transport/delegate until close completion. Quit waits for
        // this, with a bound in case macOS never delivers the close notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            guard closing else { return }
            onDiagnostic?("RFCOMM close notification timed out; releasing the channel.")
            finishClose()
        }
    }
    @objc private func channelDidClose(_ notification: IOBluetoothUserNotification, channel closedChannel: IOBluetoothRFCOMMChannel) {
        guard closing, closedChannel == channel else { return }
        onDiagnostic?("RFCOMM close confirmed.")
        finishClose()
    }
    private func finishClose() {
        closing = false; openingRFCOMM = false
        closeNotification?.unregister(); closeNotification = nil
        if !writeBuffers.isEmpty {
            // The SDK owns these buffers until writeComplete, even if its close
            // notification timed out. Retain the old delegate/storage until those
            // completions arrive; never free buffers under a pending async write.
            retiredChannel = channel
        } else if let channel { detachIfOwned(channel) }
        channel = nil; device = nil
        lease.release()
        let completions = closeCompletions; closeCompletions.removeAll()
        for completion in completions { completion() }
    }
    private func detachIfOwned(_ channel: IOBluetoothRFCOMMChannel) {
        let id = ObjectIdentifier(channel)
        guard Self.channelOwners[id]?.value === self else { return }
        _ = channel.setDelegate(nil)
        Self.channelOwners.removeValue(forKey: id)
    }
    private func fail(_ message: String) { close(); onError?(message) }
    deinit {
        openingTimer?.invalidate()
        closeNotification?.unregister()
        if let channel { detachIfOwned(channel); _ = channel.close() }
        for buffer in writeBuffers.values { buffer.deallocate() }
    }
}
