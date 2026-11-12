import Foundation
import ServiceManagement

/// juistd as Priel's LaunchDaemon, `me.0x23.priel.juistd`. Root runs it from a root-owned copy of
/// the app's helpers, never from the app, which the user can rewrite. The daemon keeps juistd
/// running while the switch's file exists, so turning the VPN on and off is creating and removing
/// that file: no password. Installing the copy, and updating it after Priel is updated, asks for
/// one (Helper.swift).
public enum JuistService {
    public static let helperDirectory = "/Library/PrivilegedHelperTools/me.0x23.priel"
    public static let plistPath = "/Library/LaunchDaemons/me.0x23.priel.juistd.plist"
    /// Owned by the user who installed, so their Priel flips the switch; root only checks that
    /// the switch exists.
    public static let stateDirectory = "/Library/Application Support/Priel"
    public static var switchPath: String { stateDirectory + "/on" }

    public static var isOn: Bool { FileManager.default.fileExists(atPath: switchPath) }

    public static var installed: Bool {
        FileManager.default.fileExists(atPath: plistPath) && FileManager.default.fileExists(atPath: helperDirectory + "/juistd-launch")
    }

    /// Turns juistd on or off; the daemon follows within a second.
    public static func set(on: Bool) throws {
        if on {
            try Data().write(to: URL(fileURLWithPath: switchPath))
        } else if isOn {
            try FileManager.default.removeItem(atPath: switchPath)
        }
    }

    /// Start the app at login.
    public static var startsAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    public static func setStartsAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
