import SwiftUI

@main
struct HeadEQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = EQModel()
    @StateObject private var backgroundSounds = BackgroundSoundsModel()
    @StateObject private var systemAudio = SystemAudioModel()
    @StateObject private var sync = SyncService()
    @StateObject private var updates = UpdateChecker()
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true

    init() {
        DSPBenchmark.runIfRequested()   // exits when HEADEQ_BENCHMARK is set
    }

    var body: some Scene {
        Window("HeadEQ", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(backgroundSounds)
                .environmentObject(systemAudio)
                .environmentObject(sync)
                .onAppear {
                    appDelegate.model = model
                    if model.settings.features.sync { sync.start(model: model) }
                    if model.settings.features.autoUpdates { updates.start() }
                    model.settings.features.launchAtLogin = LaunchAtLogin.isEnabled   // the system owns the truth
                }
                .onChange(of: model.settings.features.sync) { _, on in on ? sync.start(model: model) : sync.stop() }
                .onChange(of: model.settings.features.autoUpdates) { _, on in on ? updates.start() : updates.stop() }
                .onChange(of: model.settings.features.launchAtLogin) { _, on in
                    if on != LaunchAtLogin.isEnabled, LaunchAtLogin.set(on) != nil {
                        model.settings.features.launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
                .environmentObject(updates)
        }
        .defaultSize(width: 1140, height: 800)
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }

        Window("About HeadEQ", id: "about") {
            AboutView().environmentObject(updates)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("HeadEQ Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 900, height: 620)

        Settings {
            SettingsView().environmentObject(model).environmentObject(updates)
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
            Button("Check for Updates…") { openWindow(id: "about") }
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
