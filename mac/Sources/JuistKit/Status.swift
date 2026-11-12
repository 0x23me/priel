import Foundation

/// What juistd says about this device and its network: the part of its
/// status (`ipc.Status` in juist 0.27.1) the app shows. Keys are juist's CBOR
/// keys; fields the app does not show are not modelled.
public struct Status: Equatable, Sendable {
    public var selfIdentity = Data()
    public var selfName = ""
    public var addresses: [String] = []
    public var networkName = ""
    public var inNetwork = false
    public var joining = false
    public var notMember = false
    public var canOperate = false
    public var operatorName = ""
    /// The tunnel device, as `utun9`.
    public var device = ""
    public var instance = 0

    public var members = 0
    public var peers = 0
    public var tunnelsChecked = false
    public var tunnelsLive = 0
    public var homeRelay = ""
    public var reach: [PeerReach] = []
    public var devices: [Device] = []
    public var subnetsOff = false
    public var subnets: [SubnetRoute] = []
    /// Why the network's names are not resolved here, as "DNS is off on this device".
    public var namesNot = ""

    public var startError = ""
    public var alarm = ""
    public var disabled = ""
    public var dataPlaneError = ""
    public var epochError = ""
    public var schemaAlarm = ""
    public var stale = false
    public var refused = false

    public init() {}
}

/// One installed peer and how the last check reached it.
public struct PeerReach: Equatable, Sendable {
    /// Zero bytes in a reader's view, where juistd does not say who it is.
    public var identity = Data()
    public var live = false
    public var direct = false
    /// The member whose relay carries a relayed tunnel.
    public var relay = ""
    public var seeking = false
    public var absent = false
    /// When the tunnel was first found down.
    public var since: Date?
    /// When the peer last signed its announcement.
    public var heard: Date?
    public var outdated = false
    public var olderBuild = false
    /// The macOS patch's figures, present when asked for.
    public var handshake: Date?
    public var rxBytes: UInt64 = 0
    public var txBytes: UInt64 = 0

    public init() {}
}

/// A member as the network's log lists it; empty in a reader's view.
public struct Device: Equatable, Sendable {
    public var identity = Data()
    public var name = ""
    public var v4 = ""
    public var v6 = ""
    public var roles: [String] = []
    public var subnets: [String] = []

    public init() {}
}

/// A subnet the network routes through a member, and whether this device uses it.
public struct SubnetRoute: Equatable, Sendable {
    public var prefix = ""
    public var routerName = ""
    public var inUse = false
    public var why = ""

    public init() {}
}

// MARK: Decoding

extension Status {
    public init(cbor s: CBOR) {
        selfIdentity = s[1]?.data ?? Data()
        addresses = s[2]?.array?.compactMap { $0.data.flatMap(Prefix.string) } ?? []
        networkName = s[4]?.string ?? ""
        members = s[7]?.int ?? 0
        peers = s[8]?.int ?? 0
        alarm = s[10]?.string ?? ""
        epochError = s[11]?.string ?? ""
        notMember = s[16]?.bool ?? false
        dataPlaneError = s[19]?.string ?? ""
        schemaAlarm = s[20]?.string ?? ""
        selfName = s[24]?.string ?? ""
        stale = s[28]?.bool ?? false
        inNetwork = s[29]?.bool ?? false
        canOperate = s[30]?.bool ?? false
        operatorName = s[31]?.string ?? ""
        joining = s[32]?.bool ?? false
        startError = s[33]?.string ?? ""
        tunnelsChecked = s[39]?.bool ?? false
        tunnelsLive = s[40]?.int ?? 0
        reach = s[42]?.array?.map(PeerReach.init(cbor:)) ?? []
        homeRelay = s[44]?.string ?? ""
        devices = s[45]?.array?.map(Device.init(cbor:)) ?? []
        refused = s[52]?.bool ?? false
        instance = s[58]?.int ?? 0
        device = s[60]?.string ?? ""
        if let sub = s[64] {
            subnetsOff = sub[1]?.bool ?? false
            subnets = sub[5]?.array?.map(SubnetRoute.init(cbor:)) ?? []
        }
        namesNot = s[65]?[3]?.string ?? ""
        disabled = s[71]?.string ?? ""
    }
}

extension PeerReach {
    init(cbor r: CBOR) {
        identity = r[1]?.data ?? Data()
        live = r[2]?.bool ?? false
        direct = r[3]?.bool ?? false
        seeking = r[4]?.bool ?? false
        absent = r[5]?.bool ?? false
        since = r[6]?.int.flatMap(Self.date)
        heard = r[7]?.int.flatMap(Self.date)
        outdated = r[9]?.bool ?? false
        olderBuild = r[10]?.bool ?? false
        relay = r[11]?.string ?? ""
        handshake = r[100]?.int.flatMap(Self.date)
        rxBytes = r[101]?.uint64 ?? 0
        txBytes = r[102]?.uint64 ?? 0
    }

    /// Unix seconds, nil for zero, which juist writes for "never".
    static func date(_ seconds: Int) -> Date? {
        seconds > 0 ? Date(timeIntervalSince1970: TimeInterval(seconds)) : nil
    }
}

extension Device {
    init(cbor d: CBOR) {
        identity = d[1]?.data ?? Data()
        name = d[2]?.string ?? ""
        v4 = d[3]?.string ?? ""
        v6 = d[4]?.string ?? ""
        roles = d[5]?.array?.compactMap(\.string) ?? []
        subnets = d[8]?.array?.compactMap { $0.data.flatMap(Prefix.string) } ?? []
    }
}

extension SubnetRoute {
    init(cbor r: CBOR) {
        prefix = r[1]?.data.flatMap(Prefix.string) ?? ""
        routerName = r[3]?.string ?? ""
        inUse = r[4]?.bool ?? false
        why = r[5]?.string ?? ""
    }
}

/// Go's binary form of a `netip.Prefix`: the address (4 or 16 bytes, an IPv6
/// zone after it) and the prefix length in the last byte.
enum Prefix {
    static func string(_ d: Data) -> String? {
        let b = [UInt8](d)
        guard b.count >= 5 else { return nil }
        let bits = Int(b[b.count - 1])
        if b.count == 5 {
            return b[0..<4].map(String.init).joined(separator: ".") + "/\(bits)"
        }
        guard b.count >= 17 else { return nil }
        var addr = in6_addr()
        withUnsafeMutableBytes(of: &addr) { $0.copyBytes(from: b[0..<16]) }
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &addr, &buf, socklen_t(buf.count)) != nil else { return nil }
        return String(cString: buf) + "/\(bits)"
    }
}
