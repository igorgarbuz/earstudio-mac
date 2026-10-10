#if !SWIFT_PACKAGE
import XCTest
import AppKit
import IOBluetooth
@testable import EarStudioCompanion

// Synthetic IOBluetoothDevice deallocation can initialize Apple's coordinator
// synchronously on the main thread, waiting for a callback on that same thread.
// Keep fake objects alive for this test process; no Bluetooth operations are run.
enum BluetoothTestObjects {
    static let device = IOBluetoothDevice()
    private static var retained: [IOBluetoothDevice] = []
    static func keep<T: IOBluetoothDevice>(_ device: T) -> T { retained.append(device); return device }
}

final class ConnectionLifecycleTests: XCTestCase {
    private let device = DiscoveredDevice(device: BluetoothTestObjects.device)

    private func drainMainQueue() {
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    func testPairedDeviceInitializationLeavesMainRunLoopAvailable() {
        let published = expectation(description: "Paired devices published")
        let transport = BluetoothTransport(readPairedDevices: {
            XCTAssertFalse(Thread.isMainThread)
            // Model the coordinator waiting for work on the main queue.
            DispatchQueue.main.sync {}
            return []
        })
        transport.onDevices = { devices in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(devices.isEmpty)
            published.fulfill()
        }
        transport.loadPaired()
        wait(for: [published], timeout: 2)
    }

    func testReconnectWaitsForOldControlChannelToClose() {
        let first = FakeControlTransport(), second = FakeControlTransport()
        var transports: [ControlTransport] = [first, second]
        let model = StudioModel(makeTransport: { transports.removeFirst() })
        model.connect(device)
        drainMainQueue()
        XCTAssertEqual(first.connectCount, 1)

        model.connect(device)
        drainMainQueue()
        XCTAssertEqual(model.phase, .connecting)
        XCTAssertEqual(second.connectCount, 0)
        XCTAssertEqual(first.closeCount, 1)

        first.completeClose()
        drainMainQueue()
        XCTAssertEqual(second.connectCount, 1)
        model.disconnect()
        second.completeClose()
    }

    func testCancelWhileClosingDoesNotStartQueuedConnection() {
        let first = FakeControlTransport(), second = FakeControlTransport()
        var transports: [ControlTransport] = [first, second]
        let model = StudioModel(makeTransport: { transports.removeFirst() })
        model.connect(device)
        drainMainQueue()
        model.connect(device)
        model.disconnect()
        first.completeClose()
        drainMainQueue()
        XCTAssertEqual(second.connectCount, 0)
        XCTAssertEqual(model.phase, .disconnected)
    }

    func testQuitWaitsForCloseAndNeverReconnects() {
        let first = FakeControlTransport(), second = FakeControlTransport()
        var transports: [ControlTransport] = [first, second]
        let model = StudioModel(makeTransport: { transports.removeFirst() })
        model.connect(device)
        drainMainQueue()
        model.connect(device) // a reconnect is already waiting for close

        let delegate = EarStudioAppDelegate()
        delegate.model = model
        var replies = 0
        delegate.finishTermination = { _ in replies += 1 }
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
        drainMainQueue()
        XCTAssertEqual(replies, 0)

        first.completeClose()
        drainMainQueue()
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(second.connectCount, 0)
    }

    func testQuitWhileDisconnectedRepliesAfterReturningTerminateLater() {
        let model = StudioModel()
        let delegate = EarStudioAppDelegate()
        delegate.model = model
        var replies = 0
        delegate.finishTermination = { _ in replies += 1 }
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
        XCTAssertEqual(replies, 0)
        drainMainQueue()
        XCTAssertEqual(replies, 1)
    }

    func testSynchronousOpenCallbackIsHandledAfterChannelAssignment() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        let transport = BluetoothTransport()
        var opened = 0
        transport.onOpen = { opened += 1 }
        transport.connect(device)
        XCTAssertEqual(opened, 0)
        drainMainQueue()
        XCTAssertEqual(opened, 1)
        transport.close()
        transport.rfcommChannelClosed(device.testChannel)
    }

    func testFailedOpenWithNilChannelReportsErrorWithoutWaitingForTimeout() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.openStatus = 913
        let transport = BluetoothTransport()
        var error: String?
        transport.onError = { error = $0.message }
        transport.connect(device)
        drainMainQueue()
        XCTAssertTrue(error?.contains("913") == true)
        XCTAssertEqual(device.testChannel.closeCount, 1)
        transport.rfcommChannelClosed(device.testChannel)
    }

    func testPermissionDeniedOpeningChannelDoesNotRequestLinkReset() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.openStatus = kIOReturnNotPermitted
        let transport = BluetoothTransport()
        var failure: TransportFailure?
        transport.onError = { failure = $0 }
        transport.connect(device); drainMainQueue()
        XCTAssertNotNil(failure)
        XCTAssertEqual(failure?.allowsLinkReset, false)
        XCTAssertEqual(failure?.allowsControlRetry, false)
        transport.rfcommChannelClosed(device.testChannel)
    }

    func testStalledControlOpenUsesShortDeadlineAndAllowsControlRetry() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.deliverOpenCallback = false
        let transport = BluetoothTransport(openingTimeouts: .init(discovery: 2, control: 0.03))
        let failed = expectation(description: "Control deadline")
        transport.onError = { failure in
            XCTAssertTrue(failure.allowsControlRetry)
            XCTAssertTrue(failure.allowsLinkReset)
            XCTAssertTrue(failure.message.contains("settings connection"))
            failed.fulfill()
        }
        transport.connect(device)
        wait(for: [failed], timeout: 1)
        transport.rfcommChannelClosed(device.testChannel)
    }

    func testDiscoveryTimeoutDoesNotSpendAnotherDeadlineOnControlRetry() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.deliverSDPCallback = false
        let transport = BluetoothTransport(openingTimeouts: .init(discovery: 0.03, control: 2))
        let failed = expectation(description: "Discovery deadline")
        transport.onError = { failure in
            XCTAssertFalse(failure.allowsControlRetry)
            XCTAssertTrue(failure.allowsLinkReset)
            failed.fulfill()
        }
        transport.connect(device)
        wait(for: [failed], timeout: 1)
        XCTAssertEqual(device.openCount, 0)
    }

    func testDeadlineRecognizesOpenChannelBeforeFailingWithoutCallback() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.deliverOpenCallback = false
        let transport = BluetoothTransport(openingTimeouts: .init(discovery: 2, control: 0.03))
        let opened = expectation(description: "Deadline checks channel state")
        transport.onError = { _ in XCTFail("Channel opened without a delegate callback") }
        transport.onOpen = { opened.fulfill() }
        transport.connect(device)
        device.testChannel.open = true
        wait(for: [opened], timeout: 1)
        transport.close(); transport.rfcommChannelClosed(device.testChannel)
    }

    func testTransportCloseRetainsDelegateUntilCompletionAndIsIdempotent() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        let transport = BluetoothTransport()
        transport.connect(device)
        drainMainQueue()
        var completed = 0
        transport.close { completed += 1 }
        transport.close { completed += 1 }
        XCTAssertEqual(completed, 0)
        XCTAssertEqual(device.testChannel.closeCount, 1)
        XCTAssertFalse(device.testChannel.delegateCleared)
        transport.rfcommChannelClosed(device.testChannel)
        XCTAssertEqual(completed, 2)
        XCTAssertTrue(device.testChannel.delegateCleared)
        transport.rfcommChannelClosed(device.testChannel)
        XCTAssertEqual(completed, 2)
    }

    func testExistingOpenChannelDoesNotNeedAnOpenCallback() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.deliverOpenCallback = false
        device.testChannel.open = true
        let transport = BluetoothTransport()
        var opened = 0
        transport.onOpen = { opened += 1 }
        transport.connect(device)
        drainMainQueue()
        XCTAssertEqual(opened, 1)
        XCTAssertFalse(device.testChannel.delegateCleared)
        transport.close(); transport.rfcommChannelClosed(device.testChannel)
    }

    func testMissingOpenCallbackRecognizesChannelOpeningAfterSDP() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.deliverOpenCallback = false
        let transport = BluetoothTransport()
        var opened = 0
        transport.onOpen = { opened += 1 }
        transport.connect(device)
        XCTAssertEqual(device.queryCount, 1)
        XCTAssertEqual(device.openCount, 1)
        XCTAssertEqual(opened, 0)
        device.testChannel.open = true
        transport.checkOpeningProgress()
        XCTAssertEqual(opened, 1)

        // A late SDP callback must not start a second RFCOMM open.
        transport.sdpQueryComplete(device, status: kIOReturnSuccess)
        transport.checkOpeningProgress()
        XCTAssertEqual(device.openCount, 1)
        XCTAssertEqual(opened, 1)
        transport.close(); transport.rfcommChannelClosed(device.testChannel)
    }

    func testFullSDPCompletesWhenFilteredSDPWouldNeverCallBack() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.hasCachedService = false
        let transport = BluetoothTransport()
        var opened = 0
        transport.onOpen = { opened += 1 }
        transport.connect(device)
        drainMainQueue()
        XCTAssertEqual(device.queryCount, 1)
        XCTAssertEqual(device.openCount, 1)
        XCTAssertEqual(opened, 1)
        transport.close(); transport.rfcommChannelClosed(device.testChannel)
    }

    func testExistingChannelAndDuplicateCallbackOnlyOpenOnce() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.testChannel.open = true
        let transport = BluetoothTransport()
        var opened = 0
        transport.onOpen = { opened += 1 }
        transport.connect(device)
        drainMainQueue()
        XCTAssertEqual(opened, 1)
        transport.sdpQueryComplete(device, status: 0)
        drainMainQueue()
        XCTAssertEqual(device.openCount, 1)
        XCTAssertEqual(opened, 1)
        transport.close(); transport.rfcommChannelClosed(device.testChannel)
    }

    func testLateSuccessfulOpenAfterCancelClosesChannelWithoutAuthenticating() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.deliverOpenCallback = false
        let transport = BluetoothTransport()
        var opened = 0
        transport.onOpen = { opened += 1 }
        transport.connect(device)
        transport.close()
        device.testChannel.open = true
        transport.rfcommChannelOpenComplete(device.testChannel, status: 0)
        drainMainQueue()
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(device.testChannel.closeCount, 2)
        transport.rfcommChannelClosed(device.testChannel)
    }

    func testOnlyOneControlLeaseCanOwnTheChannelAndReleaseAllowsReopen() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let first = ControlChannelLease(), second = ControlChannelLease()
        XCTAssertTrue(first.acquire(at: path))
        XCTAssertFalse(second.acquire(at: path))
        first.release()
        XCTAssertTrue(second.acquire(at: path))
        second.release()
        XCTAssertTrue(first.acquire(at: path))
    }

    func testAppInstanceLeaseCoversDisconnectedWindowsAndReleasesOnExit() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        var first: AppInstanceGuard? = AppInstanceGuard()
        let second = AppInstanceGuard()
        XCTAssertEqual(first?.claim(at: path), .primary)
        XCTAssertEqual(first?.claim(at: path), .primary)
        XCTAssertEqual(second.claim(at: path), .duplicate)
        first = nil
        // A stale file is harmless: only the kernel lease represents ownership.
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(second.claim(at: path), .primary)
    }

    func testDuplicateAppActivatesOwnerAndTerminatesWithoutDisconnectingIt() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let first = EarStudioAppDelegate(), second = EarStudioAppDelegate()
        var activations = 0, terminations = 0
        first.enforceSingleInstance(at: path)
        XCTAssertFalse(first.isSecondaryInstance)
        second.activateExistingInstance = { activations += 1 }
        second.terminateSecondaryInstance = { terminations += 1 }
        second.reportInstanceError = { _ in XCTFail("A busy lease is not a startup error") }
        second.enforceSingleInstance(at: path)
        XCTAssertTrue(second.isSecondaryInstance)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(terminations, 1)
        XCTAssertEqual(second.applicationShouldTerminate(.shared), .terminateNow)
        XCTAssertFalse(first.isSecondaryInstance)
    }

    func testUnavailableInstanceLockReportsErrorAndDoesNotLaunchAnotherOwner() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing/instance.lock")
        let delegate = EarStudioAppDelegate()
        var errors = 0, terminations = 0
        delegate.activateExistingInstance = { XCTFail("There is no existing owner") }
        delegate.terminateSecondaryInstance = { terminations += 1 }
        delegate.reportInstanceError = { code in XCTAssertNotEqual(code, 0); errors += 1 }
        delegate.enforceSingleInstance(at: path)
        XCTAssertTrue(delegate.isSecondaryInstance)
        XCTAssertEqual(errors, 1)
        XCTAssertEqual(terminations, 1)
    }

    func testInstanceLockDoesNotFollowASymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target"), link = root.appendingPathComponent("link")
        try Data("unchanged".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let guardInstance = AppInstanceGuard()
        guard case .unavailable = guardInstance.claim(at: link) else { return XCTFail("Symlink must be refused") }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "unchanged")
    }

    func testConnectAutomaticallyRecoversOnceAfterOpeningFailure() {
        let first = FakeControlTransport(), second = FakeControlTransport()
        var links: [ControlTransport] = [first, second]
        var resetDone: ((IOReturn) -> Void)?
        var resets = 0
        let model = StudioModel(makeTransport: { links.removeFirst() }, resetBluetooth: { _, done in
            resets += 1; resetDone = done
        })
        model.connect(device); drainMainQueue()
        XCTAssertEqual(model.phase, .connecting)
        XCTAssertEqual(resets, 0, "Try opening control without interrupting audio first")

        first.onError?(TransportFailure(message: "Opening timed out", allowsLinkReset: true))
        XCTAssertEqual(model.phase, .recovering)
        XCTAssertNil(model.message, "Recovery is progress, not a final error")
        model.requestConnection() // Ignore repeated clicks during recovery.
        XCTAssertEqual(resets, 0, "Wait for the previous channel to close")
        first.onOpen?(); first.onError?(TransportFailure(message: "Late failure", allowsLinkReset: true))
        XCTAssertEqual(model.phase, .recovering)
        first.completeClose(); drainMainQueue()
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(second.connectCount, 0)
        resetDone?(0)
        XCTAssertEqual(second.connectCount, 1)
        first.onOpen?(); first.onClose?()
        XCTAssertEqual(model.phase, .connecting, "Ignore callbacks from the replaced channel")
        second.onOpen?()
        XCTAssertEqual(model.phase, .authenticating)
        XCTAssertEqual(resets, 1)
        model.disconnect(); second.completeClose()
    }

    func testCancelRecoveryBeforeCloseDoesNotResetOrReconnect() {
        let first = FakeControlTransport()
        let model = StudioModel(makeTransport: { first }, resetBluetooth: { _, _ in XCTFail("Cancelled before reset") })
        model.connect(device); drainMainQueue()
        first.onError?(TransportFailure(message: "Opening timed out", allowsLinkReset: true))
        model.cancelConfirmation()
        first.completeClose(); drainMainQueue()
        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertEqual(first.connectCount, 1)
    }

    func testRecoveryFailureStopsAndConnectStartsANewAttemptForSameDevice() {
        let first = FakeControlTransport(), second = FakeControlTransport(), third = FakeControlTransport()
        var links: [ControlTransport] = [first, second, third]
        var resets = 0
        let model = StudioModel(makeTransport: { links.removeFirst() }, resetBluetooth: { _, done in
            resets += 1; done(0)
        })
        model.connect(device); drainMainQueue()
        first.onError?(TransportFailure(message: "Opening timed out", allowsLinkReset: true))
        first.completeClose(); drainMainQueue()
        XCTAssertEqual(second.connectCount, 1)
        second.onError?(TransportFailure(message: "Still unavailable", allowsLinkReset: true))
        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertTrue(model.message?.contains("Still unavailable") == true)
        XCTAssertEqual(resets, 1, "Do not loop on a failed recovery")
        XCTAssertEqual(third.connectCount, 0)

        model.requestConnection()
        XCTAssertFalse(model.showConnection, "Retry the selected device without another device picker")
        second.completeClose(); drainMainQueue()
        XCTAssertEqual(third.connectCount, 1)
        third.onOpen?()
        XCTAssertEqual(model.phase, .authenticating)
        XCTAssertEqual(resets, 1)
        model.disconnect(); third.completeClose()
    }

    func testSuccessfulOpeningNeverResetsBluetooth() {
        let link = FakeControlTransport()
        let model = StudioModel(makeTransport: { link }, resetBluetooth: { _, _ in XCTFail("Control opened normally") })
        model.connect(device); drainMainQueue()
        model.requestConnection()
        model.prepareConnection()
        XCTAssertFalse(model.showConnection)
        XCTAssertEqual(link.connectCount, 1)
        link.onOpen?()
        XCTAssertEqual(model.phase, .authenticating)
        model.disconnect(); link.completeClose()
    }

    func testNonRecoverableFailureDoesNotResetBluetooth() {
        let link = FakeControlTransport()
        let model = StudioModel(makeTransport: { link }, resetBluetooth: { _, _ in XCTFail("Permission or ownership failure") })
        model.connect(device); drainMainQueue()
        link.onError?(TransportFailure(message: "Bluetooth permission denied"))
        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertTrue(model.message?.contains("Bluetooth permission denied") == true)
        link.completeClose()
    }

    func testFailureAfterOpeningDoesNotRetryAuthenticationOrSettings() {
        let link = FakeControlTransport()
        let model = StudioModel(makeTransport: { link }, resetBluetooth: { _, _ in XCTFail("Recovery is only for opening") })
        model.connect(device); drainMainQueue()
        link.onOpen?()
        // Even a misclassified error cannot reset/replay an authenticated session.
        link.onError?(TransportFailure(message: "Transmission failed", allowsLinkReset: true))
        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertEqual(link.connectCount, 1)
        link.completeClose()
    }

    func testChannelClosingDuringOpeningTriggersOneRecovery() {
        let first = FakeControlTransport(), second = FakeControlTransport(), third = FakeControlTransport()
        var links: [ControlTransport] = [first, second, third]
        var resets = 0
        let model = StudioModel(makeTransport: { links.removeFirst() }, resetBluetooth: { _, done in
            resets += 1; done(0)
        })
        model.connect(device); drainMainQueue()
        first.onClose?()
        first.completeClose(); drainMainQueue()
        XCTAssertEqual(second.connectCount, 1)
        XCTAssertEqual(resets, 0)
        second.onClose?()
        second.completeClose(); drainMainQueue()
        XCTAssertEqual(third.connectCount, 1)
        third.onClose?(); third.completeClose(); drainMainQueue()
        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertEqual(resets, 1)
    }

    func testLateOpenFromOldAttemptCannotCloseReusedChannel() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.deliverOpenCallback = false
        let first = BluetoothTransport(), second = BluetoothTransport()
        first.connect(device)
        first.close(); first.rfcommChannelClosed(device.testChannel)
        second.connect(device)
        device.testChannel.open = true
        let closes = device.testChannel.closeCount
        first.rfcommChannelOpenComplete(device.testChannel, status: 0)
        drainMainQueue()
        XCTAssertEqual(device.testChannel.closeCount, closes)
        second.close(); second.rfcommChannelClosed(device.testChannel)
    }

    func testControlRetryCanOpenWithoutResettingAudio() {
        let first = FakeControlTransport(), second = FakeControlTransport()
        var links: [ControlTransport] = [first, second]
        let model = StudioModel(makeTransport: { links.removeFirst() }, resetBluetooth: { _, _ in XCTFail("Keep the audio link") })
        model.connect(device); drainMainQueue()
        first.onError?(TransportFailure(message: "Control stalled", allowsLinkReset: true, allowsControlRetry: true))
        XCTAssertEqual(model.phase, .retrying)
        XCTAssertTrue(model.isBusy)
        model.requestConnection(); model.prepareConnection()
        XCTAssertFalse(model.showConnection)
        XCTAssertEqual(second.connectCount, 0, "Wait until the pending channel has closed")
        first.onOpen?(); first.onClose?()
        XCTAssertEqual(model.phase, .retrying)
        first.completeClose(); drainMainQueue()
        XCTAssertEqual(second.connectCount, 1)
        second.onOpen?()
        XCTAssertEqual(model.phase, .authenticating)
        model.disconnect(); second.completeClose()
    }

    func testFailedControlRetryResetsOnceThenStopsOnFinalFailure() {
        let first = FakeControlTransport(), retry = FakeControlTransport(), final = FakeControlTransport()
        var links: [ControlTransport] = [first, retry, final]
        var resets = 0
        let model = StudioModel(makeTransport: { links.removeFirst() }, resetBluetooth: { _, done in resets += 1; done(0) })
        let failure = TransportFailure(message: "Control stalled", allowsLinkReset: true, allowsControlRetry: true)
        model.connect(device); drainMainQueue()
        first.onError?(failure); first.completeClose(); drainMainQueue()
        XCTAssertEqual(resets, 0)
        retry.onError?(failure)
        XCTAssertEqual(model.phase, .recovering)
        retry.completeClose(); drainMainQueue()
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(final.connectCount, 1)
        first.onOpen?(); retry.onClose?(); retry.onError?(failure)
        XCTAssertEqual(model.phase, .connecting)
        final.onError?(failure)
        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertEqual(resets, 1)
        XCTAssertTrue(links.isEmpty)
        final.completeClose()
    }

    func testCancelControlRetryBeforeCloseCannotOpenAnotherChannel() {
        let first = FakeControlTransport()
        let model = StudioModel(makeTransport: { first }, resetBluetooth: { _, _ in XCTFail("Cancelled") })
        model.connect(device); drainMainQueue()
        first.onError?(TransportFailure(message: "Control stalled", allowsLinkReset: true, allowsControlRetry: true))
        model.cancelConfirmation()
        first.completeClose(); drainMainQueue()
        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertEqual(first.connectCount, 1)
    }

    func testControlRetryPermissionFailureDoesNotReset() {
        let first = FakeControlTransport(), retry = FakeControlTransport()
        var links: [ControlTransport] = [first, retry]
        let model = StudioModel(makeTransport: { links.removeFirst() }, resetBluetooth: { _, _ in XCTFail("Permission failure") })
        model.connect(device); drainMainQueue()
        first.onError?(TransportFailure(message: "Control stalled", allowsLinkReset: true, allowsControlRetry: true))
        first.completeClose(); drainMainQueue()
        retry.onError?(TransportFailure(message: "Permission denied"))
        XCTAssertEqual(model.phase, .disconnected)
        retry.completeClose()
    }

    func testOverviewProductPhotoIsIncludedInAppBundle() {
        XCTAssertNotNil(NSImage(named: "ES100Product"), "The Overview photo must ship in the compiled asset catalog")
    }

    func testBluetoothResetWaitsForObservedDisconnectBeforeReopening() {
        let device = BluetoothTestObjects.keep(FakeResetDevice())
        var waits = 0
        let result = BluetoothLinkReset.reconnect(device) { _ in
            waits += 1
            XCTAssertEqual(device.openCount, 0)
            if waits == 3 { device.connected = false }
        }
        XCTAssertEqual(result, 0)
        XCTAssertEqual(waits, 3)
        XCTAssertEqual(device.openCount, 1)
    }

    func testBluetoothResetDoesNotReopenWhenDisconnectNeverSettles() {
        let device = BluetoothTestObjects.keep(FakeResetDevice())
        var waits = 0
        XCTAssertEqual(BluetoothLinkReset.reconnect(device) { _ in waits += 1 }, kIOReturnTimeout)
        XCTAssertEqual(waits, 50)
        XCTAssertEqual(device.openCount, 0)
    }

    func testBluetoothResetPropagatesCloseAndReopenErrors() {
        let device = BluetoothTestObjects.keep(FakeResetDevice())
        device.closeStatus = 913
        XCTAssertEqual(BluetoothLinkReset.reconnect(device) { _ in XCTFail("Close failed") }, 913)
        XCTAssertEqual(device.openCount, 0)
        device.closeStatus = 0
        device.connected = false
        device.openStatus = 914
        XCTAssertEqual(BluetoothLinkReset.reconnect(device) { _ in XCTFail("Already disconnected") }, 914)
        XCTAssertEqual(device.openCount, 1)
    }

    func testCancelBluetoothRecoveryNeverStartsAControlConnection() {
        let first = FakeControlTransport(), second = FakeControlTransport()
        var links: [ControlTransport] = [first, second]
        var resetDone: ((IOReturn) -> Void)?
        let model = StudioModel(makeTransport: { links.removeFirst() }, resetBluetooth: { _, done in resetDone = done })
        model.connect(device); drainMainQueue()
        first.onError?(TransportFailure(message: "The ES100 control channel did not open.", allowsLinkReset: true))
        first.completeClose(); drainMainQueue()
        model.cancelConfirmation()
        resetDone?(0); drainMainQueue()
        XCTAssertEqual(second.connectCount, 0)
        XCTAssertEqual(model.phase, .disconnected)
    }

    func testFailedBluetoothResetIsActionableAndDoesNotRetryWrites() {
        let first = FakeControlTransport()
        let model = StudioModel(makeTransport: { first }, resetBluetooth: { _, done in done(913) })
        model.connect(device); drainMainQueue()
        first.onError?(TransportFailure(message: "The ES100 control channel did not open.", allowsLinkReset: true))
        first.completeClose(); drainMainQueue()
        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertTrue(model.message?.contains("913") == true)
        XCTAssertEqual(first.connectCount, 1)
    }

    func testCloseKeepsAsyncWriteStorageAliveUntilWriteCompletion() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.testChannel.open = true
        let transport = BluetoothTransport()
        transport.connect(device); drainMainQueue()
        let bytes = Data([0xFF, 1, 0, 0, 0xA5, 0x5A, 0, 0])
        XCTAssertTrue(transport.send(bytes))
        let pointer = device.testChannel.writePointer!
        let token = device.testChannel.writeToken!
        transport.close(); transport.rfcommChannelClosed(device.testChannel)
        XCTAssertFalse(device.testChannel.delegateCleared)
        XCTAssertEqual(Data(bytes: pointer, count: bytes.count), bytes)
        transport.rfcommChannelWriteComplete(device.testChannel, refcon: token, status: 0)
        XCTAssertTrue(device.testChannel.delegateCleared)
    }

    func testReusedChannelCannotReleaseNewWritesOrClearTheNewDelegate() {
        let device = BluetoothTestObjects.keep(FakeBluetoothDevice())
        device.testChannel.open = true
        let first = BluetoothTransport(), second = BluetoothTransport()
        first.connect(device); drainMainQueue()
        XCTAssertTrue(first.send(Data([1, 2, 3])))
        let oldToken = device.testChannel.writeToken!
        first.close(); first.rfcommChannelClosed(device.testChannel)
        second.connect(device); drainMainQueue()
        let bytes = Data([4, 5, 6])
        XCTAssertTrue(second.send(bytes))
        let newToken = device.testChannel.writeToken!, pointer = device.testChannel.writePointer!
        XCTAssertNotEqual(oldToken, newToken)
        second.rfcommChannelWriteComplete(device.testChannel, refcon: oldToken, status: 913)
        XCTAssertFalse(device.testChannel.delegateCleared)
        XCTAssertEqual(Data(bytes: pointer, count: bytes.count), bytes)
        second.rfcommChannelWriteComplete(device.testChannel, refcon: newToken, status: 0)
        second.close(); second.rfcommChannelClosed(device.testChannel)
        XCTAssertTrue(device.testChannel.delegateCleared)
    }
}

private final class FakeResetDevice: IOBluetoothDevice {
    var connected = true
    var closeStatus: IOReturn = 0
    var openStatus: IOReturn = 0
    var openCount = 0
    override func isConnected() -> Bool { connected }
    override func closeConnection() -> IOReturn { closeStatus }
    override func openConnection() -> IOReturn {
        XCTAssertFalse(connected)
        openCount += 1
        return openStatus
    }
}

private final class FakeBluetoothDevice: IOBluetoothDevice {
    let testChannel = FakeRFCOMMChannel()
    private let service = FakeSerialService()
    var openStatus: IOReturn = kIOReturnSuccess
    var deliverOpenCallback = true
    var deliverSDPCallback = true
    var hasCachedService = true
    var queryCount = 0
    var openCount = 0

    override var addressString: String! { nil }

    override func isConnected() -> Bool { true }
    override func performSDPQuery(_ target: Any!) -> IOReturn {
        queryCount += 1
        hasCachedService = true
        if deliverSDPCallback { (target as? BluetoothTransport)?.sdpQueryComplete(self, status: kIOReturnSuccess) }
        return kIOReturnSuccess
    }
    override func performSDPQuery(_ target: Any!, uuids uuidArray: [Any]!) -> IOReturn {
        // Reproduce the macOS 15.7.9 behavior: accepts the filtered request,
        // but never invokes sdpQueryComplete. Tests must use the full query.
        return kIOReturnSuccess
    }
    override func getServiceRecord(for sdpUUID: IOBluetoothSDPUUID!) -> IOBluetoothSDPServiceRecord! {
        hasCachedService ? service : nil
    }
    override func openRFCOMMChannelAsync(_ rfcommChannel: AutoreleasingUnsafeMutablePointer<IOBluetoothRFCOMMChannel?>!, withChannelID channelID: BluetoothRFCOMMChannelID, delegate channelDelegate: Any!) -> IOReturn {
        // Deliberately invoke the delegate before assigning the out parameter.
        openCount += 1
        if deliverOpenCallback {
            (channelDelegate as? BluetoothTransport)?.rfcommChannelOpenComplete(openStatus == 0 ? testChannel : nil, status: openStatus)
        }
        rfcommChannel.pointee = testChannel
        return kIOReturnSuccess
    }
}

private final class FakeSerialService: IOBluetoothSDPServiceRecord {
    override func getRFCOMMChannelID(_ channelID: UnsafeMutablePointer<BluetoothRFCOMMChannelID>!) -> IOReturn {
        channelID.pointee = 1
        return kIOReturnSuccess
    }
}

private final class FakeRFCOMMChannel: IOBluetoothRFCOMMChannel {
    var closeCount = 0
    var delegateCleared = false
    var open = false
    var writePointer: UnsafeMutableRawPointer?
    var writeToken: UnsafeMutableRawPointer?
    override func isOpen() -> Bool { open }
    override func getMTU() -> BluetoothRFCOMMMTU { 64 }
    override func writeAsync(_ data: UnsafeMutableRawPointer!, length: UInt16, refcon: UnsafeMutableRawPointer!) -> IOReturn {
        writePointer = data; writeToken = refcon; return 0
    }
    override func close() -> IOReturn { closeCount += 1; return kIOReturnSuccess }
    override func setDelegate(_ delegate: Any!) -> IOReturn {
        delegateCleared = delegate == nil
        return kIOReturnSuccess
    }
    override func register(forChannelCloseNotification observer: Any!, selector inSelector: Selector!) -> IOBluetoothUserNotification! { nil }
}

private final class FakeControlTransport: ControlTransport {
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onError: ((TransportFailure) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var connectCount = 0
    var closeCount = 0
    private var completions: [() -> Void] = []

    func connect(_ target: IOBluetoothDevice) { connectCount += 1 }
    func send(_ data: Data) -> Bool { true }
    func close(completion: @escaping () -> Void) {
        closeCount += 1; completions.append(completion)
    }
    func completeClose() {
        let pending = completions; completions.removeAll()
        pending.forEach { $0() }
    }
}
#endif
