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
    private(set) var service = JuistService.state
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
            if service == .needsApproval { return .attention("Allow Priel in Login Items to turn the VPN on.") }
            return switching == true || service == .on ? .connecting : .off
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
        guard switching == nil else { return }
        switching = on
        actionError = nil
        Task {
            do {
                try JuistService.set(on: on)
            } catch {
                actionError = error.localizedDescription
            }
            service = JuistService.state
            if on && service == .needsApproval { JuistService.openLoginItems() }
            // Wait for juistd to answer or to stop answering, up to ten seconds.
            for _ in 0..<20 where actionError == nil && service != .needsApproval {
                await refresh()
                if running == on { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            switching = nil
        }
    }

    /// Joins the network the invite code is for, making the logged-in user the operator.
    func join(_ code: String) {
        asRoot([Self.juist, "join", code, "--operator", NSUserName()])
    }

    /// Makes the logged-in user this device's operator, for names and latency.
    func becomeOperator() {
        asRoot([Self.juist, "set", "--operator", NSUserName()])
    }

    /// Links `juist` in /usr/local/bin to the app's copy.
    func installCommandLine() {
        asRoot(["/bin/sh", "-c", "mkdir -p /usr/local/bin && ln -sf \"$0\" /usr/local/bin/juist", Self.juist])
    }

    /// The app's own `juist`, which matches the juistd it runs.
    static var juist: String { Bundle.main.bundleURL.appending(path: "Contents/MacOS/juist").path }

    static func findCommandLine() -> Bool {
        ["/usr/local/bin/juist", "/opt/homebrew/bin/juist"].contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func asRoot(_ args: [String]) {
        guard !asking else { return }
        asking = true
        actionError = nil
        Task {
            // HOME is root's, so the command line's cache does not land root-owned in the user's Library.
            actionError = await Admin.run(["/usr/bin/env", "HOME=/var/root"] + args)
            commandLineInstalled = Self.findCommandLine()
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

    /// Cuts the current wait short, so opening the window shows fresh figures.
    private func wake() {
        sleeper?.cancel()
    }

    /// Reads the counters, and the status too when status is set.
    private func refresh(status fetch: Bool = true) async {
        service = JuistService.state
        if fetch {
            let client = client, figures = figures
            let answer = await Task.detached { () -> Result<Status, Error> in
                Result { try client.status(figures: figures) }
            }.value
            switch answer {
            case .success(let s):
                status = s
            case .failure(JuistError.daemon(_)) where figures:
                // A juistd without the patch refuses the unknown field; ask without it from the next tick.
                self.figures = false
            case .failure:
                status = nil
            }
        }
        let device = status?.device ?? ""
        let counters = device.isEmpty ? nil : await Task.detached { InterfaceCounters.read(device) }.value
        meter.add(counters, at: Date())
        if status == nil { latency = [:] }
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
