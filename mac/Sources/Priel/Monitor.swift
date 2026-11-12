import Foundation
import JuistKit
import Observation

/// What the app knows about juistd, refreshed by polling: the status every
/// 2 s while the window is open and every 5 s while it is closed, the
/// tunnel's counters every second while open and every 5 s while closed,
/// and the operator's pings every 5 s while the window is open only.
@MainActor @Observable
final class Monitor {
    enum Phase: Equatable {
        case off, connecting, connected
        /// Running, or meant to, but something is wrong: the one line says what.
        case attention(String)
    }

    /// The last answer; nil while juistd does not answer.
    private(set) var status: Status?
    /// The switch's file, and the root-owned copy the daemon runs.
    private(set) var on = JuistService.isOn
    private(set) var helper = Helper.state
    private(set) var meter = TrafficMeter()
    /// Round trips by member identity.
    private(set) var latency: [Data: TimeInterval] = [:]
    /// The state a click asked for, until juistd is in it.
    private(set) var switching: Bool?
    /// What went wrong with the last click: the switch, joining, or a command run as root.
    private(set) var actionError: String?
    private(set) var startsAtLogin = JuistService.startsAtLogin
    /// A command run through the administrator prompt is under way.
    private(set) var asking = false
    private(set) var commandLineInstalled = Monitor.findCommandLine()
    /// Split DNS: Priel's list, and what is in /etc/resolver now.
    private(set) var dns: [Resolver] = []
    private(set) var resolverFiles: [(resolver: Resolver, ours: Bool)] = []

    var open = false {
        didSet { if open && !oldValue { wake() } }
    }

    /// JUIST_SOCKET points the app at another juistd, as a test daemon.
    private let client = JuistClient(socketPath: ProcessInfo.processInfo.environment["JUIST_SOCKET"] ?? JuistClient.systemSocket)
    /// Off once a juistd without the macOS patch has refused the figures.
    private var figures = true
    private var tick = 0
    private var sleeper: Task<Void, Never>?

    init() {
        Task { await run() }
    }

    var running: Bool { status != nil }

    var phase: Phase {
        guard let s = status else {
            if on && helper == .missing { return .attention("Priel's background part is not installed. Turn the VPN off and on.") }
            return switching == true || on ? .connecting : .off
        }
        for problem in [s.startError, s.dataPlaneError, s.alarm, s.epochError, s.schemaAlarm, s.disabled] where !problem.isEmpty {
            return .attention(problem)
        }
        if s.notMember { return .attention("This device is no longer a member of \(s.networkName).") }
        if !s.inNetwork { return s.joining ? .connecting : .attention("This device is in no juist network yet.") }
        if !s.tunnelsChecked { return .connecting }
        if s.peers > 0 && s.tunnelsLive == 0 { return .attention("No other device is reached.") }
        return .connected
    }

    /// The switch's state: juistd's, or where a click is taking it.
    var isOn: Bool { switching ?? running }

    func turn(on: Bool) {
        guard switching == nil, !asking else { return }
        switching = on
        actionError = nil
        Task {
            if on && helper != .current {
                // Installs or updates the copy root runs, and turns on: the one password.
                asking = true
                if let install = Helper.install {
                    actionError = await Admin.run(install, why: "Priel wants to install juistd, owned by root, to run the VPN.")
                    // Installed, not cancelled: now the switch, which is this user's to flip.
                    if actionError == nil, await Helper.check() == .current {
                        do { try JuistService.set(on: true) } catch { actionError = error.localizedDescription }
                    }
                } else {
                    actionError = "This copy of Priel is not signed with a Developer ID, so it cannot check what it would have root run."
                }
                asking = false
            } else {
                do {
                    try JuistService.set(on: on)
                } catch {
                    actionError = error.localizedDescription
                }
            }
            self.on = JuistService.isOn
            helper = await Helper.check()
            // Wait for juistd to answer or to stop answering, up to fifteen seconds.
            for _ in 0..<30 where actionError == nil && self.on == on {
                await refresh()
                if running == on { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            switching = nil
        }
    }

    /// Updates the copy root runs to this Priel's, after Priel itself was updated.
    func updateHelper() {
        guard let install = Helper.install else { return }
        asRoot(install, home: false, why: "Priel wants to update juistd to the version in this Priel.")
    }

    /// Joins the network the invite code is for, making the logged-in user the operator.
    /// The code goes on root's command line, which other users can see while it runs: juist join
    /// takes it no other way. It is used once, and juist invite's words are checked besides.
    func join(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !code.hasPrefix("-"), !code.contains(where: \.isWhitespace) else {
            actionError = "That is not an invite code: a code is one word, like 42-drumbeat-tolerance-glucose."
            return
        }
        asRoot([Helper.tool("juist"), "join", code, "--operator", NSUserName()], why: "Priel wants to join this Mac to a juist network.")
    }

    /// Makes the logged-in user this device's operator, for names and latency.
    func becomeOperator() {
        asRoot([Helper.tool("juist"), "set", "--operator", NSUserName()], why: "Priel wants to make you this Mac's juist operator.")
    }

    /// Links `juist` in /usr/local/bin to the root-owned copy, which matches the juistd that runs.
    func installCommandLine() {
        asRoot(["/bin/sh", "-c", "mkdir -p /usr/local/bin && ln -sfh \"$0\" /usr/local/bin/juist", Helper.tool("juist")], why: "Priel wants to put the juist command in /usr/local/bin.")
    }

    /// Replaces the split DNS list; priel-dns rewrites /etc/resolver at once while juistd runs.
    func setDNS(_ list: [Resolver]) {
        asRoot([Helper.tool("priel-dns"), "set"] + list.flatMap { [$0.domain, $0.server] }, why: "Priel wants to change which domains it sends to which DNS server.")
    }

    /// Domains in /etc/resolver Priel did not write, whose server is in a subnet the network
    /// routes: the hand-made files Priel can take over.
    var foundDNS: [Resolver] {
        let prefixes = status?.subnets.map(\.prefix) ?? []
        return resolverFiles.filter { file in
            !file.ours && !dns.contains { $0.domain == file.resolver.domain } && prefixes.contains { file.resolver.server(in: $0) }
        }.map(\.resolver)
    }

    /// Whether a domain's file is Priel's and says what the list says.
    func dnsActive(_ r: Resolver) -> Bool {
        resolverFiles.contains { $0.ours && $0.resolver == r }
    }

    static func findCommandLine() -> Bool {
        ["/usr/local/bin/juist", "/opt/homebrew/bin/juist"].contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func asRoot(_ args: [String], home: Bool = true, why: String) {
        guard !asking else { return }
        asking = true
        actionError = nil
        Task {
            // HOME is root's, so the command line's cache does not land root-owned in the user's Library.
            actionError = await Admin.run(home ? ["/usr/bin/env", "HOME=/var/root"] + args : args, why: why)
            commandLineInstalled = Self.findCommandLine()
            helper = await Helper.check()
            await refresh()
            asking = false
        }
    }

    func setStartsAtLogin(_ on: Bool) {
        try? JuistService.setStartsAtLogin(on)
        startsAtLogin = JuistService.startsAtLogin
    }

    private func run() async {
        while true {
            await refresh(status: !open || tick % 2 == 0)
            if open && tick % 5 == 0 { await ping() }
            tick += 1
            let seconds = open ? 1 : 5
            let task = Task { _ = try? await Task.sleep(for: .seconds(seconds)) }
            sleeper = task
            await task.value
        }
    }

    /// Cuts the current wait short, so opening the window shows fresh figures, and checks the
    /// root-owned copy again, which an update elsewhere may have changed.
    private func wake() {
        sleeper?.cancel()
        Task { helper = await Helper.check() }
    }

    /// Reads the counters, and the status too when status is set.
    private func refresh(status fetch: Bool = true) async {
        on = JuistService.isOn
        if fetch {
            let client = client, figures = figures
            let answer = await Task.detached { () -> (Result<Status, Error>, refused: Bool) in
                let first = Result { try client.status(figures: figures) }
                // A juistd without the patch refuses the unknown field. Only an answer to the same
                // question without it says that is why; any other error is the daemon's.
                guard figures, case .failure(JuistError.daemon(_)) = first,
                      let plain = try? client.status(figures: false) else { return (first, false) }
                return (.success(plain), true)
            }.value
            switch answer.0 {
            case .success(let s):
                status = s
                if answer.refused { self.figures = false }
            case .failure(JuistError.daemon(_)):
                break
            case .failure:
                status = nil
                // Whichever juistd answers next may be one with the patch.
                self.figures = true
            }
            readDNS()
        }
        let device = status?.device ?? ""
        let counters = device.isEmpty ? nil : await Task.detached { InterfaceCounters.read(device) }.value
        meter.add(counters, at: Date())
        if status == nil { latency = [:] }
    }

    /// PRIEL_ETC and PRIEL_RESOLVER_DIR point the app at other files, for rendering it with sample
    /// ones; priel-dns, which root runs, takes no such thing.
    private func readDNS() {
        let env = ProcessInfo.processInfo.environment
        let list = env["PRIEL_ETC"].map { $0 + "/resolvers" } ?? Resolver.listPath
        dns = (try? String(contentsOfFile: list, encoding: .utf8)).map(Resolver.list) ?? []
        resolverFiles = Resolver.files(in: env["PRIEL_RESOLVER_DIR"] ?? Resolver.systemDirectory)
    }

    private func ping() async {
        guard let s = status, s.canOperate else { return }
        let client = client
        let members = s.reach.filter { $0.live && $0.identity.contains { $0 != 0 } }.map(\.identity)
        let results = await withTaskGroup(of: (Data, TimeInterval?).self) { group in
            for member in members {
                group.addTask { (member, try? client.ping(member, timeout: 3)) }
            }
            return await group.reduce(into: [Data: TimeInterval]()) { $0[$1.0] = $1.1 }
        }
        latency = results.compactMapValues { $0 }
    }
}

extension Monitor.Phase {
    var symbol: String {
        switch self {
        case .off: "network.slash"
        case .connecting: "circle.dotted"
        case .connected: "network"
        case .attention: "exclamationmark.triangle"
        }
    }

    var label: String {
        switch self {
        case .off: "off"
        case .connecting: "connecting"
        case .connected: "connected"
        case .attention: "needs attention"
        }
    }
}
