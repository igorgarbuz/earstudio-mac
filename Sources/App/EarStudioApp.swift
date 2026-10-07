import SwiftUI

@main
struct EarStudioApp: App {
    @StateObject private var model = StudioModel(demo: CommandLine.arguments.contains("--demo"))
    var body: some Scene {
        Window("EarStudio Companion", id: "main") {
            StudioView().environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(StudioTheme.green)
                .onDisappear { model.disconnect() }
        }
        .defaultSize(width: 1180, height: 850)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Connect to EarStudio…") { model.prepareConnection() }.keyboardShortcut("k")
                Button("Refresh Device Settings") { model.refresh() }.keyboardShortcut("r").disabled(!model.canEdit || model.isDemo)
                Divider()
                Button("Import EQ Presets…") { model.importPresets() }
                Button("Export EQ Presets…") { model.exportPresets() }
            }
            CommandMenu("Device") {
                Button("Disconnect") { model.disconnect() }.disabled(model.phase == .disconnected)
                Button("Explore Demo") { model.enterDemo() }.disabled(model.isDemo || model.isBusy)
                Button("Diagnostics…") { model.showDiagnostics = true }
            }
        }
    }
}
