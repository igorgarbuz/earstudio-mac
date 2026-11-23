import Foundation
import XCTest
import EarStudioSession

extension XCTestCase {
    func makeSession(demo: Bool = false, defaults injectedDefaults: UserDefaults? = nil) -> DeviceSession {
        let suite = "EarStudioSessionTests.\(UUID().uuidString)"
        let defaults = injectedDefaults ?? UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let session = DeviceSession(demo: demo, defaults: defaults,
            saveDeviceKey: { _, _ in true }, readDeviceKey: { _ in 0 }, forgetDeviceKey: { _ in true })
        addTeardownBlock { session.disconnect() }
        return session
    }
}
