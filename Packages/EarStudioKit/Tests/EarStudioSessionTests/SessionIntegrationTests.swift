import Foundation
import XCTest
import EarStudioCore
import EarStudioSession

final class SessionIntegrationTests: XCTestCase {
    func testImportedPresetsPersistInInjectedStoreAndRoundTripWithoutDialogs() throws {
        let suite = "SessionPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func make() -> DeviceSession {
            DeviceSession(defaults: defaults, saveDeviceKey: { _, _ in true },
                          readDeviceKey: { _ in 0 }, forgetDeviceKey: { _ in true })
        }
        let session = make()
        let data = try JSONEncoder().encode(PresetFile(presets: [.flat]))
        try session.importPresets(from: data)
        XCTAssertEqual(session.presets.count, 1)
        XCTAssertNotEqual(session.presets[0].id, EQPreset.flat.id)
        let restored = make()
        XCTAssertEqual(restored.presets, session.presets)
        XCTAssertEqual(try PresetFile.decode(restored.exportPresets()), session.presets)
        session.deletePreset(session.presets[0].id)
        XCTAssertTrue(make().presets.isEmpty)
    }

    func testFailedImportPreservesStoredPresets() throws {
        let session = makeSession()
        try session.importPresets(from: JSONEncoder().encode(PresetFile(presets: [.flat])))
        let original = session.presets
        XCTAssertThrowsError(try session.importPresets(from: Data("invalid".utf8)))
        XCTAssertEqual(session.presets, original)
    }

    func testOpeningFailureWithoutPlatformResetStopsAfterControlRetry() {
        let session = makeSession()
        var attempts = 0
        session.connect(DeviceConnection(id: "test", name: "ES100", makeTransport: {
            attempts += 1
            return FailedOpeningTransport()
        }))
        let finished = expectation(description: "Opening attempts finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { finished.fulfill() }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(session.phase, .disconnected)
        XCTAssertNotNil(session.message)
    }
}

private final class FailedOpeningTransport: SessionTransport {
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((TransportFailure) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    func open() {
        onError?(TransportFailure(message: "Opening failed", allowsLinkReset: true, allowsControlRetry: true))
    }
    func send(_ data: Data) -> Bool { false }
    func close(completion: @escaping () -> Void) { completion() }
}
