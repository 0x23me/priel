import Foundation
import JuistKit
import Security

/// The root-owned copy of what root runs: juist, juistd, the daemon's launcher and priel-dns, in
/// JuistService.helperDirectory, and the LaunchDaemon that runs the launcher. Installing copies
/// them out of the app as root, then, owned by root so nothing can change them in between, checks
/// that each is signed by this app's team. Root never runs a file from the app itself.
enum Helper {
    enum State { case missing, outdated, current }

    static let tools = ["juist", "juistd", "juistd-launch", "priel-dns"]

    /// The root-owned copy of a tool, the one to run as root.
    static func tool(_ name: String) -> String { JuistService.helperDirectory + "/" + name }

    static func bundled(_ name: String) -> String { Bundle.main.bundleURL.appending(path: "Contents/MacOS/\(name)").path }

    /// Current when each copy's signature is the app's own tool's. The app's are read once; the
    /// copies when asked, which the app does when its window opens and after it installs.
    static var state: State {
        guard JuistService.installed else { return .missing }
        let same = tools.allSatisfy { name in cdhash(tool(name)).map { $0 == bundledHashes[name] } ?? false }
        return same ? .current : .outdated
    }

    /// state, read away from the main thread.
    static func check() async -> State {
        await Task.detached { state }.value
    }

    private static let bundledHashes = Dictionary(uniqueKeysWithValues: tools.compactMap { name in cdhash(bundled(name)).map { (name, $0) } })

    static func cdhash(_ path: String) -> Data? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
    }

    /// The team that signed this app, whose signature each copy must carry.
    static var team: String? {
        var me: SecCode?, code: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// The command that installs or updates the copy and the daemon, to run as root. Nil for an
    /// app not signed by a team, whose tools nothing could check. It leaves the switch alone: the
    /// app flips that itself, in a directory root never writes into.
    static var install: [String]? {
        guard let team else { return nil }
        return ["/bin/sh", "-c", script, "priel-install", Bundle.main.bundlePath, team, NSUserName()]
    }

    // The values come in as arguments, not as text in the script.
    private static let script = #"""
        set -eu
        app=$1 team=$2 user=$3
        case $team in '' | *[!A-Z0-9]*) echo "not a team ID: $team" >&2; exit 1 ;; esac
        id -u "$user" >/dev/null
        h=/Library/PrivilegedHelperTools/me.0x23.priel
        plist=/Library/LaunchDaemons/me.0x23.priel.juistd.plist
        state="/Library/Application Support/Priel"
        mkdir -p /Library/PrivilegedHelperTools
        new=$(mktemp -d /Library/PrivilegedHelperTools/.me.0x23.priel.XXXXXX)
        trap 'rm -rf "$new"' EXIT
        for t in juist juistd juistd-launch priel-dns; do
            ditto "$app/Contents/MacOS/$t" "$new/$t"
        done
        # ditto carries ACLs and file flags across, and an ACL can grant your user write access
        # that neither the mode nor the signature shows: none of either on what root runs. Flags
        # first, since an immutable file refuses the ACL's removal.
        chflags 0 "$new"/*
        chmod -N "$new"/*
        chown -R root:wheel "$new"
        chmod 755 "$new"/*
        for t in juist juistd juistd-launch priel-dns; do
            codesign --verify --strict -R="identifier \"me.0x23.priel.$t\" and anchor apple generic and certificate leaf[subject.OU] = \"$team\"" "$new/$t" ||
                { echo "$t in Priel is not signed by team $team" >&2; exit 1; }
        done
        # Readable once checked; mktemp made it root's alone.
        chmod 755 "$new"
        if [ -d "$h" ]; then rm -rf "$h.old"; mv "$h" "$h.old"; fi
        mv "$new" "$h"
        trap - EXIT
        rm -rf "$h.old"
        # The user's directory, for the switch. Admins can write to /Library/Application Support, so
        # it may be a link someone made: -h changes the link itself, never what it points to.
        mkdir -p "$state"
        chown -h "$user" "$state"
        chmod -h 755 "$state"
        cat > "$plist.new" <<PLIST
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>me.0x23.priel.juistd</string>
          <key>Program</key><string>$h/juistd-launch</string>
          <key>AssociatedBundleIdentifiers</key><array><string>me.0x23.priel</string></array>
          <key>EnvironmentVariables</key><dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>StandardOutPath</key><string>/var/log/juistd.log</string>
          <key>StandardErrorPath</key><string>/var/log/juistd.log</string>
        </dict></plist>
        PLIST
        chown root:wheel "$plist.new"
        chmod 644 "$plist.new"
        mv -f "$plist.new" "$plist"
        launchctl bootout system/me.0x23.priel.juistd 2>/dev/null || true
        # bootout returns before the job is gone, and bootstrap fails while it is there.
        i=0
        while launchctl print system/me.0x23.priel.juistd >/dev/null 2>&1 && [ $i -lt 100 ]; do
            sleep 0.2
            i=$((i + 1))
        done
        launchctl bootstrap system "$plist"
        # A juist command linked to an earlier Priel's own copy now runs root's.
        case $(readlink /usr/local/bin/juist 2>/dev/null || true) in
        */Priel.app/*) ln -sfh "$h/juist" /usr/local/bin/juist ;;
        esac
        """#
}
