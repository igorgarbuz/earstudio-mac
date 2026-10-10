import SwiftUI

/// A kernel lease covers the entire process lifetime, including disconnected
/// and demo windows. It is automatically released after a crash. The lock file
/// must stay in place: unlinking it could let two processes lock different files.
final class AppInstanceGuard {
    enum Claim: Equatable { case primary, duplicate, unavailable(Int32) }
    private let lease = ControlChannelLease()

    func claim(at url: URL) -> Claim {
        if lease.acquire(at: url) { return .primary }
        switch lease.failure {
        case .occupied: return .duplicate
        case .unavailable(let code): return .unavailable(code)
        case nil: return .unavailable(0)
        }
    }
}

final class EarStudioAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: StudioModel?
    var finishTermination: (NSApplication) -> Void = { $0.reply(toApplicationShouldTerminate: true) }
    private var terminating = false
    private let instanceGuard = AppInstanceGuard()
    private(set) var isSecondaryInstance = false
    var activateExistingInstance: () -> Void = {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing else { return }
        existing.unhide()
        NSApplication.shared.yieldActivation(to: existing)
        _ = existing.activate(options: [])
    }
    var terminateSecondaryInstance: () -> Void = { NSApplication.shared.terminate(nil) }
    var reportInstanceError: (Int32) -> Void = { code in
        let alert = NSAlert()
        alert.messageText = "EarStudio Companion could not start safely"
        alert.informativeText = "The application ownership lock could not be opened (error \(code)). Try reopening the app."
        alert.runModal()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Hosted XCTest has its own process and never connects to real hardware.
        // Keep that host independent of a user's running Companion window.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        enforceSingleInstance(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("earstudio-companion-instance.lock"))
    }

    func enforceSingleInstance(at url: URL) {
        switch instanceGuard.claim(at: url) {
        case .primary: break
        case .duplicate:
            isSecondaryInstance = true
            activateExistingInstance()
            terminateSecondaryInstance()
        case .unavailable(let code):
            isSecondaryInstance = true
            reportInstanceError(code)
            terminateSecondaryInstance()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isSecondaryInstance else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        guard let model else { return .terminateNow }
        terminating = true
        model.disconnect {
            // Even an already-closed connection must reply after this method
            // returns terminateLater, not synchronously from inside it.
            DispatchQueue.main.async { self.finishTermination(sender) }
        }
        return .terminateLater
    }
}

@main
struct EarStudioApp: App {
    @NSApplicationDelegateAdaptor(EarStudioAppDelegate.self) private var appDelegate
    @StateObject private var model = StudioModel(demo: CommandLine.arguments.contains("--demo"))
    var body: some Scene {
        Window("EarStudio Companion", id: "main") {
            StudioView().environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(StudioTheme.green)
                .onAppear { appDelegate.model = model }
                .onDisappear { model.disconnect() }
        }
        .defaultSize(width: 1180, height: 850)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Connect to EarStudio…") { model.requestConnection() }.keyboardShortcut("k").disabled(model.isBusy)
                Button("Refresh Device Settings") { model.refresh() }.keyboardShortcut("r").disabled(!model.canEdit || model.isDemo)
                Divider()
                Button("Import EQ Presets…") { model.importPresets() }
                Button("Export EQ Presets…") { model.exportPresets() }
            }
            CommandMenu("Device") {
                Button("Disconnect") { model.disconnect() }.disabled(model.phase == .disconnected)
                Button(model.isDemo ? "Exit Demo" : "Try Demo") { model.isDemo ? model.disconnect() : model.enterDemo() }
                    .disabled(model.isBusy || model.phase == .connected)
                Button("Diagnostics…") { model.showDiagnostics = true }
            }
        }
    }
}
