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
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: model.becameActive()
                    case .background: model.enteredBackground()
                    default: break
                    }
                }
        }
    }
}
