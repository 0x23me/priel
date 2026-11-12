import Foundation
import ServiceManagement

/// juistd as the launchd daemon the app carries (`me.0x23.priel.juistd.plist` in
/// `Contents/Library/LaunchDaemons`). Registering starts it and keeps it
/// started across restarts; unregistering stops it and keeps it stopped.
/// The first registration needs the owner's approval in Login Items, which
/// is asked once: later registrations after an unregistration are not.
public enum JuistService {
    static var daemon: SMAppService { SMAppService.daemon(plistName: "me.0x23.priel.juistd.plist") }

    public enum State: Equatable, Sendable {
        case off
        case on
        case needsApproval
        /// The app is not a bundle carrying the daemon, as under `swift run`.
        case notFound
    }

    public static var state: State {
        switch daemon.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        case .notFound: .notFound
        default: .off
        }
    }

    /// Turns juistd on or off. Turning on before approval does not throw:
    /// the state becomes `needsApproval`, and Login Items is the place to
    /// give it.
    public static func set(on: Bool) throws {
        do {
            if on { try daemon.register() } else { try daemon.unregister() }
        } catch {
            if on, daemon.status == .requiresApproval { return }
            throw error
        }
    }

    public static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Start the app at login.
    public static var startsAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    public static func setStartsAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
