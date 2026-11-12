import Darwin
import Foundation

/// A network interface's byte counters as the kernel keeps them, 64-bit.
public struct InterfaceCounters: Equatable, Sendable {
    /// The interface's index; a new one means the interface was made anew.
    public var index: Int
    public var rxBytes: UInt64
    public var txBytes: UInt64

    public init(index: Int, rxBytes: UInt64, txBytes: UInt64) {
        self.index = index
        self.rxBytes = rxBytes
        self.txBytes = txBytes
    }

    /// The counters of the interface named name, nil where there is none.
    /// Read with `NET_RT_IFLIST2`, whose `if_data64` does not wrap at 4 GiB
    /// as `getifaddrs`'s 32-bit counters do. Needs no privileges.
    public static func read(_ name: String) -> InterfaceCounters? {
        let index = Int(if_nametoindex(name))
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> InterfaceCounters? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let m = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if Int(m.ifm_index) == index {
                        return InterfaceCounters(index: index, rxBytes: m.ifm_data.ifi_ibytes, txBytes: m.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
            return nil
        }
    }
}

/// Receive and send rates in bytes per second.
public struct Rate: Equatable, Sendable {
    public var rx: Double
    public var tx: Double

    public init(rx: Double, tx: Double) {
        self.rx = rx
        self.tx = tx
    }
}

/// The tunnel's rate over the last samples and its totals. Totals are the
/// counters, which start at zero when juistd makes the interface; a sample
/// from a new interface, or smaller counters, starts the history afresh
/// rather than showing a spike.
public struct TrafficMeter: Sendable {
    public let capacity: Int
    public private(set) var history: [Rate] = []
    public private(set) var totals: InterfaceCounters?
    private var last: (counters: InterfaceCounters, at: Date)?

    public init(capacity: Int = 60) {
        self.capacity = capacity
    }

    public var current: Rate? { history.last }

    public mutating func add(_ counters: InterfaceCounters?, at time: Date) {
        guard let counters else {
            reset()
            return
        }
        totals = counters
        defer { last = (counters, time) }
        guard let last, last.counters.index == counters.index,
              counters.rxBytes >= last.counters.rxBytes, counters.txBytes >= last.counters.txBytes
        else {
            history.removeAll()
            return
        }
        let seconds = time.timeIntervalSince(last.at)
        guard seconds > 0 else { return }
        history.append(Rate(rx: Double(counters.rxBytes - last.counters.rxBytes) / seconds,
                            tx: Double(counters.txBytes - last.counters.txBytes) / seconds))
        if history.count > capacity { history.removeFirst(history.count - capacity) }
    }

    public mutating func reset() {
        history.removeAll()
        totals = nil
        last = nil
    }
}
