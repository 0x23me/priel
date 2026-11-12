import AppKit
import JuistKit
import SwiftUI

/// The window under the menu bar icon: the switch, this device, the network
/// with its devices and subnets, the tunnel's traffic, and one warning line.
struct JuistWindow: View {
    var monitor: Monitor
    @State private var copied: String?
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let s = monitor.status {
                Divider()
                network(s)
                if s.inNetwork {
                    Divider()
                    traffic
                }
            }
            if let warning {
                Divider()
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .section()
            }
            if monitor.service == .needsApproval {
                Divider()
                HStack {
                    Text("Priel needs your approval to run juist in the background.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Open Login Items") { JuistService.openLoginItems() }
                }
                .font(.callout)
                .section()
            }
            if monitor.status != nil && !monitor.commandLineInstalled {
                Divider()
                HStack {
                    Text("The juist command is not installed.")
                    Spacer()
                    Button("Install") { monitor.installCommandLine() }
                        .disabled(monitor.asking)
                        .help("Links /usr/local/bin/juist to the copy in Priel")
                }
                .font(.callout)
                .section()
            }
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var warning: String? {
        if let e = monitor.actionError { return e }
        // Approval and joining have their own rows, which say what to do.
        if let s = monitor.status, !s.inNetwork, !s.joining { return nil }
        if case .attention(let why) = monitor.phase, monitor.service != .needsApproval { return why }
        return nil
    }

    // MARK: Header: the switch and this device

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("juist").font(.headline)
                    // With juistd answering, the network's own line says how it is.
                    if monitor.status == nil {
                        Text(monitor.phase == .off ? "The VPN is off." : monitor.phase.label.capitalizedFirst)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if monitor.switching != nil {
                    ProgressView().controlSize(.small)
                }
                Toggle("VPN", isOn: Binding(get: { monitor.isOn }, set: { monitor.turn(on: $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(monitor.switching != nil || monitor.service == .notFound)
                    .accessibilityLabel("VPN")
            }
            if let s = monitor.status {
                HStack(spacing: 8) {
                    Text(s.selfName).fontWeight(.medium)
                    // IPv4 first: the shorter one, and the one people type.
                    ForEach(s.addresses.map(\.address).sorted { $0.contains(".") && !$1.contains(".") }, id: \.self) { address in
                        Button { copy(address) } label: {
                            Text(copied == address ? "Copied" : address)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Copy \(address)")
                        .accessibilityLabel("Copy address \(address)")
                    }
                }
                .font(.callout.monospacedDigit())
            }
        }
        .section()
    }

    private func copy(_ address: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        copied = address
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == address { copied = nil }
        }
    }

    // MARK: The network: devices and subnets

    @ViewBuilder
    private func network(_ s: Status) -> some View {
        if !s.inNetwork && !s.joining {
            join
        } else {
            members(s)
        }
    }

    /// A device in no network yet joins one with the code `juist invite` printed on a member.
    private var join: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Join a network").font(.headline)
            HStack {
                TextField("Invite code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if !code.isEmpty { monitor.join(code) } }
                Button("Join") { monitor.join(code) }
                    .disabled(code.isEmpty || monitor.asking)
            }
            Text("Run juist invite on a device in the network for a code. Joining makes you this device's operator.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .section()
    }

    private func members(_ s: Status) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.networkName.isEmpty ? "No network" : s.networkName).font(.headline)
                Spacer()
                Text(monitor.phase.label).foregroundStyle(.secondary)
            }
            ForEach(peers(s)) { PeerRow(peer: $0, latency: monitor.latency) }
            ForEach(s.subnets, id: \.prefix) { SubnetRow(route: $0, off: s.subnetsOff) }
            if !s.canOperate {
                HStack {
                    Text("Names and latency are shown to this device's operator.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Become Operator") { monitor.becomeOperator() }
                        .controlSize(.small)
                        .disabled(monitor.asking)
                        .help("Runs sudo juist set --operator \(NSUserName())")
                }
            }
        }
        .section()
    }

    /// The other members: by name for the operator, as "member 1" on in a
    /// reader's view, where juistd gives neither names nor identities.
    private func peers(_ s: Status) -> [Peer] {
        if s.devices.isEmpty {
            return s.reach.enumerated().map { Peer(id: $0.offset, name: "member \($0.offset + 1)", reach: $0.element) }
        }
        return s.devices.filter { $0.identity != s.selfIdentity }.enumerated().map { i, d in
            Peer(id: i, name: d.name, reach: s.reach.first { $0.identity == d.identity })
        }
    }

    // MARK: Traffic

    private var traffic: some View {
        let rate = monitor.meter.current
        let totals = monitor.meter.totals
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Label(rate.map { bytes($0.rx) + "/s" } ?? "–", systemImage: "arrow.down")
                    Label(rate.map { bytes($0.tx) + "/s" } ?? "–", systemImage: "arrow.up")
                }
                .font(.callout.monospacedDigit())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rate.map { "Receiving \(bytes($0.rx)) per second, sending \(bytes($0.tx)) per second" } ?? "No rate yet")
                Text(totals.map { "Total ↓ \(bytes($0.rxBytes))  ↑ \(bytes($0.txBytes))" } ?? "Total –")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(totals.map { "Total received \(bytes($0.rxBytes)), sent \(bytes($0.txBytes))" } ?? "No totals yet")
            }
            Spacer()
            Sparkline(history: monitor.meter.history, capacity: monitor.meter.capacity)
                .frame(width: 120, height: 30)
                .accessibilityHidden(true)
        }
        .section()
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Open Log") {
                let log = URL(fileURLWithPath: "/var/log/juistd.log")
                if let console = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") {
                    NSWorkspace.shared.open([log], withApplicationAt: console, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            Toggle("Start at Login", isOn: Binding(get: { monitor.startsAtLogin }, set: { monitor.setStartsAtLogin($0) }))
                .toggleStyle(.checkbox)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .controlSize(.small)
        .section()
    }
}

struct Peer: Identifiable {
    var id: Int
    var name: String
    var reach: PeerReach?
}

/// One other device: how it is reached, its latency, and while reached the
/// handshake's age and the bytes each way.
struct PeerRow: View {
    var peer: Peer
    var latency: [Data: TimeInterval]

    var body: some View {
        let r = peer.reach
        let ms = r.flatMap { latency[$0.identity] }.map { Int(($0 * 1000).rounded()) }
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(r?.live == true ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(peer.name)
                Spacer()
                Text(path).foregroundStyle(.secondary)
                if let ms { Text("\(ms) ms").monospacedDigit().frame(minWidth: 44, alignment: .trailing) }
            }
            if let r, r.live {
                HStack(spacing: 10) {
                    Text(r.handshake.map { "handshake " + ago($0) } ?? "no handshake yet")
                    Text("↓ \(bytes(r.rxBytes))  ↑ \(bytes(r.txBytes))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.leading, 13)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(ms: ms))
    }

    private var path: String {
        guard let r = peer.reach else { return "not checked yet" }
        if r.live { return r.direct ? "direct" : r.relay.isEmpty ? "relayed" : "via \(r.relay)" }
        if r.absent { return "offline" }
        if r.seeking { return "looking for it" }
        return "not reached"
    }

    private func accessibility(ms: Int?) -> String {
        var parts = [peer.name, path]
        if let r = peer.reach, r.live {
            parts.append(r.handshake.map { "handshake " + ago($0) } ?? "no handshake yet")
            parts.append("received \(bytes(r.rxBytes)), sent \(bytes(r.txBytes))")
        }
        if let ms { parts.append("latency \(ms) milliseconds") }
        return parts.joined(separator: ", ")
    }
}

/// A subnet routed through a member, and whether this device uses it.
struct SubnetRow: View {
    var route: SubnetRoute
    var off: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.secondary)
                    .frame(width: 7)
                Text(route.prefix).monospacedDigit()
                if !route.routerName.isEmpty { Text("via \(route.routerName)").foregroundStyle(.secondary) }
                Spacer()
                Text(route.inUse ? "in use" : "not in use").foregroundStyle(.secondary)
            }
            if !route.inUse, let why = off ? "subnets are off on this device" : route.why.nonEmpty {
                Text(why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 13)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Receive and send rates over the last minute, scaled to the larger.
struct Sparkline: View {
    var history: [Rate]
    var capacity: Int

    var body: some View {
        Canvas { context, size in
            // At least 1 KB/s high, so an idle tunnel's keepalives stay a flat line.
            let top = max(history.map { max($0.rx, $0.tx) }.max() ?? 0, 1024)
            let step = size.width / CGFloat(max(capacity - 1, 1))
            let start = size.width - CGFloat(history.count - 1) * step
            for (value, color) in [(\Rate.tx, Color.orange), (\Rate.rx, Color.accentColor)] {
                var line = Path()
                for (i, r) in history.enumerated() {
                    let p = CGPoint(x: start + CGFloat(i) * step, y: size.height - CGFloat(r[keyPath: value] / top) * (size.height - 1))
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                context.stroke(line, with: .color(color), lineWidth: 1.25)
            }
        }
    }
}

private extension View {
    func section() -> some View {
        padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private extension String {
    /// The address of a prefix as juist writes it: "198.18.68.2/32" is "198.18.68.2".
    var address: String { split(separator: "/").first.map(String.init) ?? self }
    var nonEmpty: String? { isEmpty ? nil : self }
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private let byteFormatter = {
    let f = ByteCountFormatter()
    f.allowsNonnumericFormatting = false
    return f
}()

func bytes<T: BinaryInteger>(_ n: T) -> String {
    byteFormatter.string(fromByteCount: Int64(clamping: n))
}

func bytes(_ n: Double) -> String {
    bytes(Int64(n.rounded()))
}

/// "12 s ago", "4 min ago", "2 h ago".
func ago(_ date: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(date)))
    return s < 60 ? "\(s) s ago" : s < 3600 ? "\(s / 60) min ago" : "\(s / 3600) h ago"
}
