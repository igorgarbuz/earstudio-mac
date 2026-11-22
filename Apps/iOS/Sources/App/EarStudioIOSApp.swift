import SwiftUI
import EarStudioUI

@main
struct EarStudioIOSApp: App {
    // Sample device state is available only to development builds and UI tests.
    #if DEBUG
    @StateObject private var model = IOSStudioModel(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
    #else
    @StateObject private var model = IOSStudioModel()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(StudioTheme.green)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    // There is no background control mode. End active work before
                    // suspension so writes are never replayed after returning.
                    if phase == .background {
                        model.stopDiscovery()
                        if !model.session.isDemo { model.disconnect() }
                    }
                }
        }
    }
}
