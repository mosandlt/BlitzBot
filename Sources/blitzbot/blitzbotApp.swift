import SwiftUI
import AppKit

final class BlitzbotAppDelegate: NSObject, NSApplicationDelegate {
    let config: AppConfig
    let processor: ModeProcessor
    let permissions: PermissionsChecker
    let hotkeys = HotkeyManager()
    var hud: RecordingHUDController?
    var rewriter: SelectionRewriter?
    private var officeCloseObserver: NSObjectProtocol?
    private var officeKeyObserver: NSObjectProtocol?

    var openWindow: ((String) -> Void)?

    override init() {
        Log.write("Delegate init")
        self.config = MainActor.assumeIsolated { AppConfig() }
        self.processor = MainActor.assumeIsolated { ModeProcessor() }
        self.permissions = MainActor.assumeIsolated { PermissionsChecker() }
        super.init()
    }

    /// Hide the Dock icon as early as possible. We *don't* use `LSUIElement=true`
    /// in Info.plist because it makes runtime transitions to `.regular` (e.g. when
    /// Office Mode opens) unreliable — macOS doesn't always show the Dock icon in
    /// that case. Setting the policy programmatically at will-finish keeps the
    /// flash at launch short and allows clean `.regular ⇄ .accessory` switches.
    func applicationWillFinishLaunching(_ notification: Notification) {
        Log.write("applicationWillFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)
        // Install the Office window observers up-front so SwiftUI auto-restored
        // windows (from a prior session) also trigger the Dock icon.
        installOfficeCloseObserverIfNeeded()
        // Belt-and-suspenders: if SwiftUI already restored an Office window
        // before `OfficeView.onAppear` got to fire `ensureOfficePolicyActive`,
        // catch up here.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if NSApp.windows.contains(where: { $0.title == "blitzbot Office" && $0.isVisible }) {
                MainActor.assumeIsolated { self.ensureOfficePolicyActive() }
            }
        }

        hotkeys.onTrigger = { [weak self] mode in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.processor.toggle(mode: mode, config: self.config)
                }
            }
        }
        hotkeys.isHoldToTalkEnabled = { [weak self] in
            self?.config.holdToTalk ?? false
        }
        hotkeys.onToggleOffice = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.toggleOfficeWindow()
                }
            }
        }
        hotkeys.register()
        // Log-Meldung kommt jetzt aus HotkeyManager.installEventTap()

        // Trigger any pending Keychain ACL prompts up-front instead of mid-recording.
        // User clicks "Always Allow" once per item and then it stays silent.
        KeychainPreWarmer.prewarm(profileStore: config.profileStore)

        // Recover any WAV files left behind by a previous run that was killed during recording.
        processor.recoverOrphanedRecordings(config: config)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.hud = RecordingHUDController(processor: self.processor, config: self.config)
                self.rewriter = SelectionRewriter(config: self.config, processor: self.processor)
                self.hotkeys.onRewriteSelection = { [weak self] in
                    guard let self, let rewriter = self.rewriter else { return }
                    Task { @MainActor in rewriter.rewriteSelection() }
                }
                Log.write("SelectionRewriter ready")
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

    /// Opens the Office window, or closes it if already visible. Matching by
    /// window title is the most stable identifier across SwiftUI/macOS versions;
    /// the internal identifier format (`SwiftUI-Window-office` etc.) has shifted
    /// before and we don't want to chase it.
    @MainActor
    func toggleOfficeWindow() {
        let windows = NSApp.windows.filter { $0.title == "blitzbot Office" }
        if let existing = windows.first(where: { $0.isVisible }) {
            existing.close()
            // The close notification observer resets the activation policy.
            Log.write("Office: window closed via toggle")
            return
        }
        // Capture the source app + current selection BEFORE we steal focus.
        // After `NSApp.activate` the frontmost app is blitzbot and the AX query
        // / ⌘C fallback would return nothing useful.
        let source = NSWorkspace.shared.frontmostApplication
        let selection = TextSelectionGrabber.grab()
        config.pendingOfficeContent = PendingOfficeContent(
            text: selection,
            sourceAppBundleID: source?.bundleIdentifier,
            createdAt: Date()
        )
        Log.write("Office: toggle — captured selection chars=\(selection.count), sourceApp=\(source?.bundleIdentifier ?? "nil")")

        // Show the app in the Dock + ⌘-Tab while Office is open so the user can
        // jump back to it from anywhere. Reverted to `.accessory` when the window
        // closes (see `installOfficeCloseObserverIfNeeded`).
        let before = NSApp.activationPolicy()
        let changed = NSApp.setActivationPolicy(.regular)
        let after = NSApp.activationPolicy()
        Log.write("Office: setActivationPolicy(.regular) before=\(before.rawValue) changed=\(changed) after=\(after.rawValue)")
        installOfficeCloseObserverIfNeeded()

        openWindow?("office")
        // Activate *after* the window is created so the Dock icon transition and
        // focus land in the right order. Some macOS versions otherwise keep
        // blitzbot hidden from the Dock until the next app activation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        }
        Log.write("Office: window opened via toggle")
    }

    /// Called by `OfficeView.onAppear` so the Dock icon appears regardless of
    /// how the window was created — hotkey toggle, menu-bar click, or SwiftUI's
    /// session-restore when blitzbot relaunches with an Office window still open.
    @MainActor
    func ensureOfficePolicyActive() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            Log.write("Office: onAppear → policy=.regular")
        }
        installOfficeCloseObserverIfNeeded()
        // Explicit activation so the Dock icon is pushed to the foreground
        // transition — on some macOS versions the `.regular` switch alone
        // doesn't populate the Dock until the next app activation.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Watches for the Office window's `willClose` and reverts the app's activation
    /// policy so blitzbot goes back to being a menu-bar-only accessory. Also
    /// watches for `didBecomeKey` so SwiftUI auto-restored Office windows (when
    /// the user quit + reopened blitzbot with the window open) get the Dock icon
    /// too — not just windows opened via the hotkey toggle.
    @MainActor
    private func installOfficeCloseObserverIfNeeded() {
        if officeCloseObserver == nil {
            officeCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow,
                      window.title == "blitzbot Office" else { return }
                DispatchQueue.main.async {
                    NSApp.setActivationPolicy(.accessory)
                    Log.write("Office: window closed, policy=.accessory")
                }
            }
        }
        if officeKeyObserver == nil {
            officeKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow,
                      window.title == "blitzbot Office" else { return }
                if NSApp.activationPolicy() != .regular {
                    NSApp.setActivationPolicy(.regular)
                    Log.write("Office: window became key, policy=.regular")
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
                .environmentObject(delegate.config.privacyEngine)
        } label: {
            MenuBarLabel()
                .environmentObject(delegate.processor)
                .onAppear { delegate.openWindow = { openWindow(id: $0) } }
        }
        .menuBarExtraStyle(.window)

        Window("blitzbot Einstellungen", id: "settings") {
            SettingsView().environmentObject(delegate.config)
        }
        .windowResizability(.contentMinSize)

        Window("blitzbot Setup", id: "setup") {
            PermissionsView()
                .environmentObject(delegate.permissions)
                .environmentObject(delegate.config)
        }
        .windowResizability(.contentSize)

        Window("blitzbot Office", id: "office") {
            OfficeView()
                .environmentObject(delegate.config)
        }
        .windowResizability(.contentMinSize)
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
        case .aufnahme:                              return "record.circle.fill"
        case .transkribiert, .korrigiert, .formuliert: return "waveform"
        case .fertig:                     return "checkmark.circle.fill"
        case .fehler, .recovery:          return "exclamationmark.triangle.fill"
        case .bereit:                     return "bolt.fill"
        }
    }

    private var tint: Color {
        switch processor.status {
        case .aufnahme:                              return .red
        case .transkribiert, .korrigiert, .formuliert: return .yellow
        case .fertig:                     return .green
        case .fehler, .recovery:          return .orange
        case .bereit:                     return .primary
        }
    }

    private var tag: String? {
        if case .aufnahme = processor.status { return "REC" }
        return nil
    }
}
