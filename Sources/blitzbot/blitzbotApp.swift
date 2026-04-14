import SwiftUI
import AppKit

final class BlitzbotAppDelegate: NSObject, NSApplicationDelegate {
    let config: AppConfig
    let processor: ModeProcessor
    let permissions: PermissionsChecker
    let hotkeys = HotkeyManager()
    var hud: RecordingHUDController?

    var openWindow: ((String) -> Void)?

    override init() {
        Log.write("Delegate init")
        self.config = MainActor.assumeIsolated { AppConfig() }
        self.processor = MainActor.assumeIsolated { ModeProcessor() }
        self.permissions = MainActor.assumeIsolated { PermissionsChecker() }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)

        hotkeys.onTrigger = { [weak self] mode in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.processor.toggle(mode: mode, config: self.config)
                }
            }
        }
        hotkeys.register()
        Log.write("Hotkeys registered (⌘⌥1-4)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.hud = RecordingHUDController(processor: self.processor, config: self.config)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.permissions.refresh(config: self.config)
                if !self.permissions.allGood {
                    Log.write("Permissions incomplete — opening setup")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    self.openWindow?("setup")
                }
            }
        }
    }
}

@main
struct BlitzbotApp: App {
    @NSApplicationDelegateAdaptor(BlitzbotAppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(delegate.processor)
                .environmentObject(delegate.config)
        } label: {
            MenuBarLabel()
                .environmentObject(delegate.processor)
                .onAppear { delegate.openWindow = { openWindow(id: $0) } }
        }
        .menuBarExtraStyle(.window)

        Window("blitzbot Einstellungen", id: "settings") {
            SettingsView().environmentObject(delegate.config)
        }
        .windowResizability(.contentSize)

        Window("blitzbot Setup", id: "setup") {
            PermissionsView()
                .environmentObject(delegate.permissions)
                .environmentObject(delegate.config)
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject var processor: ModeProcessor

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(tint)
            if let tag { Text(tag).font(.caption2.bold()) }
        }
    }

    private var symbol: String {
        switch processor.status {
        case .aufnahme:                   return "record.circle.fill"
        case .transkribiert, .formuliert: return "waveform"
        case .fertig:                     return "checkmark.circle.fill"
        case .fehler:                     return "exclamationmark.triangle.fill"
        case .bereit:                     return "bolt.fill"
        }
    }

    private var tint: Color {
        switch processor.status {
        case .aufnahme:                   return .red
        case .transkribiert, .formuliert: return .yellow
        case .fertig:                     return .green
        case .fehler:                     return .orange
        case .bereit:                     return .primary
        }
    }

    private var tag: String? {
        if case .aufnahme = processor.status { return "REC" }
        return nil
    }
}
