import Foundation

/// Invoke methods and deliver callbacks on the main thread. A transport belongs
/// to one connection attempt. close must complete only after it releases ownership.
public protocol SessionTransport: AnyObject {
    var onOpen: (() -> Void)? { get set }
    var onData: ((Data) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    var onError: ((TransportFailure) -> Void)? { get set }
    var onDiagnostic: ((String) -> Void)? { get set }
    func open()
    func send(_ data: Data) -> Bool
    func close(completion: @escaping () -> Void)
}

public struct TransportFailure {
    public let message: String
    public var allowsLinkReset: Bool
    public var allowsControlRetry: Bool

    public init(message: String, allowsLinkReset: Bool = false, allowsControlRetry: Bool = false) {
        self.message = message
        self.allowsLinkReset = allowsLinkReset
        self.allowsControlRetry = allowsControlRetry
    }
}

/// Opaque device identity and platform operations. Core code never sees a
/// Bluetooth framework object. Factories must return a fresh transport per attempt.
public struct DeviceConnection {
    public let id: String
    public let name: String
    let makeTransport: () -> SessionTransport
    let resetLink: ((@escaping (Result<Void, Error>) -> Void) -> Void)?

    public init(id: String, name: String, makeTransport: @escaping () -> SessionTransport,
                resetLink: ((@escaping (Result<Void, Error>) -> Void) -> Void)? = nil) {
        self.id = id; self.name = name; self.makeTransport = makeTransport; self.resetLink = resetLink
    }
}
