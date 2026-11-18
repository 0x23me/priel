import AppKit
import JuistKit
import SwiftUI

// Picture mode for the site and the README; debug builds only.
#if DEBUG

/// `Priel --shot connected|several|reader|join light|dark <file.png>` shows the window with a
/// made-up status, saves a picture of it with its shadow and exits. It reads nothing from juistd,
/// the switch or /etc, so no real name or address can end up in the picture.
enum Shot {
    static let request: (state: String, dark: Bool, file: String)? = {
        let arguments = CommandLine.arguments
        guard let at = arguments.firstIndex(of: "--shot"), arguments.count > at + 3 else { return nil }
        return (arguments[at + 1], arguments[at + 2] == "dark", arguments[at + 3])
    }()

    private static func identity(_ n: UInt8) -> Data { Data(repeating: n, count: 32) }

    private static func reach(_ n: UInt8, direct: Bool = true, relay: String = "", seconds: Double,
                              rx: UInt64, tx: UInt64) -> PeerReach {
        var r = PeerReach()
        r.identity = identity(n)
        r.live = true
        r.direct = direct
        r.relay = relay
        r.handshake = Date().addingTimeInterval(-seconds)
        r.rxBytes = rx
        r.txBytes = tx
        return r
    }

    private static func device(_ n: UInt8, _ name: String, subnets: [String] = []) -> Device {
        var d = Device()
        d.identity = identity(n)
        d.name = name
        d.subnets = subnets
        return d
    }

    static func status(_ state: String) -> Status {
        var s = Status()
        s.selfIdentity = identity(0)
        s.selfName = "laptop-01"
        s.addresses = ["198.18.68.2/32", "fd12:3456:789a:20fc:4c1e:9b08:5603:a0f2/128"]
        s.device = "utun9"
        guard state != "join" else { return s }
        s.networkName = "lab"
        s.inNetwork = true
        s.tunnelsChecked = true
        var route = SubnetRoute()
        route.prefix = "10.99.0.0/16"
        route.routerName = "gate"
        route.why = "this device is on a network inside it"
        s.subnets = [route]
        let gate = reach(1, seconds: 58, rx: 102_400, tx: 100_352)
        switch state {
        case "reader":
            s.reach = [gate]
        case "several":
            s.canOperate = true
            var pi = PeerReach()
            pi.identity = identity(3)
            pi.absent = true
            s.devices = [device(0, "laptop-01"), device(1, "gate", subnets: ["10.99.0.0/16"]), device(2, "nas"), device(3, "pi")]
            s.reach = [gate, reach(2, direct: false, relay: "gate", seconds: 71, rx: 48_200_000, tx: 1_900_000), pi]
        default:
            s.canOperate = true
            s.devices = [device(0, "laptop-01"), device(1, "gate", subnets: ["10.99.0.0/16"])]
            s.reach = [gate]
        }
        s.members = s.devices.isEmpty ? 2 : s.devices.count
        s.peers = s.reach.count
        s.tunnelsLive = s.reach.filter(\.live).count
        return s
    }

    /// One domain of the made-up network, sent to its gate.
    static let dns = [Resolver(domain: "home.example", server: "10.99.0.1")]

    static func latency(_ state: String) -> [Data: TimeInterval] {
        guard state != "reader" else { return [:] }
        return [identity(1): 0.004, identity(2): 0.031]
    }

    /// A minute of a download that is winding down, then the steady trickle of an idle tunnel.
    static func meter() -> TrafficMeter {
        var meter = TrafficMeter()
        var rx: UInt64 = 3_400_000, tx: UInt64 = 15_700_000
        let start = Date().addingTimeInterval(-60)
        for second in 0...60 {
            let x = Double(second)
            let wave = max(0, sin(x / 9)) * 180_000 * exp(-x / 30)
            rx += UInt64(20_000 + wave)
            tx += UInt64(10_000 + wave / 6)
            meter.add(InterfaceCounters(index: 9, rxBytes: rx, txBytes: tx), at: start.addingTimeInterval(x))
        }
        return meter
    }

    /// Called once by the menu bar item, the first view on screen. Nothing opens a MenuBarExtra's
    /// window from inside the app, so the picture is of the same view in a panel made like it.
    @MainActor static func take(_ monitor: Monitor) {
        guard let request else { return }
        NSApp.appearance = NSAppearance(named: request.dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: JuistWindow(monitor: monitor))
        let size = host.fittingSize
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        host.frame = effect.bounds
        effect.addSubview(host)
        let panel = Panel(contentRect: effect.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = effect
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            panel.invalidateShadow()
            guard let image = picture(of: panel) else { print("no picture of the window"); exit(1) }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: request.file))
            exit(0)
        }
    }

    /// A borderless panel can't become key by itself; the window it stands in for is key while open.
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    /// The window with frame and shadow (no permission needed for the app's own windows).
    /// `CGWindowListCreateImage` is gone from the SDK but still exists at runtime, hence dlsym.
    private static func picture(of window: NSWindow) -> CGImage? {
        typealias Function = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let including: UInt32 = 1 << 3, bestResolution: UInt32 = 1 << 3
        return unsafeBitCast(symbol, to: Function.self)(.null, including, UInt32(window.windowNumber), bestResolution)?
            .takeRetainedValue()
    }
}

#endif
