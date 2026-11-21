import Foundation
import IOBluetooth
import EarStudioSession

/// Binds a native Bluetooth transport to its device without exposing IOBluetooth
/// types to the shared session. The adapter preserves asynchronous close semantics.
final class MacSessionTransport: SessionTransport {
    private let transport: ControlTransport
    private let device: IOBluetoothDevice

    init(transport: ControlTransport, device: IOBluetoothDevice) {
        self.transport = transport; self.device = device
    }
    var onOpen: (() -> Void)? { get { transport.onOpen } set { transport.onOpen = newValue } }
    var onData: ((Data) -> Void)? { get { transport.onData } set { transport.onData = newValue } }
    var onClose: (() -> Void)? { get { transport.onClose } set { transport.onClose = newValue } }
    var onError: ((TransportFailure) -> Void)? { get { transport.onError } set { transport.onError = newValue } }
    var onDiagnostic: ((String) -> Void)? { get { transport.onDiagnostic } set { transport.onDiagnostic = newValue } }
    func open() { transport.connect(device) }
    func send(_ data: Data) -> Bool { transport.send(data) }
    func close(completion: @escaping () -> Void) { transport.close(completion: completion) }
}
