import SwiftUI

@main
struct HeadEQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = EQModel()
    @StateObject private var backgroundSounds = BackgroundSoundsModel()
    @StateObject private var systemAudio = SystemAudioModel()
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        Window("HeadEQ", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(backgroundSounds)
                .environmentObject(systemAudio)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1140, height: 800)
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }

        Window("About HeadEQ", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("HeadEQ Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 900, height: 620)

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView().environmentObject(model).environmentObject(backgroundSounds)
                .onAppear { backgroundSounds.refresh() }
        } label: {
            MenuBarLabel().environmentObject(model)
        }
    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About HeadEQ") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .help) {
            Button("HeadEQ Help") { openWindow(id: "help") }.keyboardShortcut("?", modifiers: .command)
            Button("User Guide (full documentation)") { HelpView.openDocs() }
            Divider()
            Link("AutoEQ headphone database", destination: URL(string: "https://github.com/jaakkopasanen/AutoEq")!)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: EQModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppIcon.apply() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        // Destroy the tap so system audio is un-muted immediately.
        MainActor.assumeIsolated { model?.shutdown() }
    }
}
