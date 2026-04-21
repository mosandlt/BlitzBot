import Foundation
import ServiceManagement

/// Thin facade over `SMAppService.mainApp` so the Settings toggle has a single
/// source of truth (the system itself — no UserDefaults mirror to drift out of
/// sync). Works only on macOS 13+; `Package.swift` already pins the deployment
/// target there, so we don't bother with `#available` guards.
@MainActor
enum LaunchAtLoginManager {
    /// True iff SMAppService reports the main app is actively scheduled to
    /// launch at login. `.requiresApproval` is treated as false on purpose —
    /// the user hasn't approved yet and the UI shouldn't pretend otherwise.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Flip the registration. Returns the resulting effective state so the UI
    /// can reconcile (e.g. after `register()` the status may be
    /// `.requiresApproval` on first use — caller sees `false` and shows the
    /// hint to open System Settings).
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> Bool {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else {
                Log.write("LaunchAtLogin: already enabled, skip")
                return true
            }
            try service.register()
            Log.write("LaunchAtLogin: register() → \(describe(service.status))")
        } else {
            guard service.status != .notRegistered else {
                Log.write("LaunchAtLogin: already disabled, skip")
                return false
            }
            try service.unregister()
            Log.write("LaunchAtLogin: unregister() → \(describe(service.status))")
        }
        return service.status == .enabled
    }

    static var statusDescription: String {
        describe(SMAppService.mainApp.status)
    }

    /// `.requiresApproval` means macOS is waiting for the user to confirm the
    /// Login Item in System Settings → General → Login Items. Surface that
    /// explicitly in the UI so the toggle doesn't look broken.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered:    return "nicht registriert"
        case .enabled:          return "aktiv"
        case .requiresApproval: return "Freigabe in Systemeinstellungen nötig"
        case .notFound:         return "App nicht gefunden (Bundle-Signatur?)"
        @unknown default:       return "unbekannt"
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .unsupportedOS: return "Launch-at-Login braucht macOS 13 oder neuer."
        }
    }
}
