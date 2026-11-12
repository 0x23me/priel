import Foundation
import Testing

@testable import JuistKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

@Test func ratesAreTheDeltaOverTime() {
    var m = TrafficMeter()
    m.add(InterfaceCounters(index: 9, rxBytes: 1000, txBytes: 100), at: t0)
    #expect(m.current == nil)
    m.add(InterfaceCounters(index: 9, rxBytes: 5000, txBytes: 300), at: t0 + 2)
    #expect(m.current == Rate(rx: 2000, tx: 100))
    #expect(m.totals?.rxBytes == 5000)
}

@Test func aRestartedDaemonStartsAfreshWithoutASpike() {
    var m = TrafficMeter()
    m.add(InterfaceCounters(index: 9, rxBytes: 10_000_000, txBytes: 1000), at: t0)
    m.add(InterfaceCounters(index: 9, rxBytes: 10_001_000, txBytes: 1000), at: t0 + 1)
    // Smaller counters: juistd made the interface anew.
    m.add(InterfaceCounters(index: 9, rxBytes: 200, txBytes: 50), at: t0 + 2)
    #expect(m.history.isEmpty)
    #expect(m.totals?.rxBytes == 200)
    m.add(InterfaceCounters(index: 9, rxBytes: 400, txBytes: 50), at: t0 + 3)
    #expect(m.current == Rate(rx: 200, tx: 0))
    // A new index, however large its counters.
    m.add(InterfaceCounters(index: 12, rxBytes: 900_000, txBytes: 50), at: t0 + 4)
    #expect(m.history.isEmpty)
}

@Test func aMissingInterfaceClearsEverything() {
    var m = TrafficMeter()
    m.add(InterfaceCounters(index: 9, rxBytes: 1, txBytes: 1), at: t0)
    m.add(nil, at: t0 + 1)
    #expect(m.totals == nil && m.history.isEmpty)
}

@Test func theHistoryKeepsTheLastMinute() {
    var m = TrafficMeter(capacity: 60)
    for i in 0...100 {
        m.add(InterfaceCounters(index: 1, rxBytes: UInt64(i * 10), txBytes: 0), at: t0 + Double(i))
    }
    #expect(m.history.count == 60)
}

@Test func readsTheLoopbackCounters() throws {
    let lo = try #require(InterfaceCounters.read("lo0"))
    #expect(lo.index > 0 && lo.rxBytes > 0)
    #expect(InterfaceCounters.read("nonexistent0") == nil)
}

/// The tunnel's counters agree with netstat's, when JUIST_LIVE_TESTS=1.
@Test(.enabled(if: ProcessInfo.processInfo.environment["JUIST_LIVE_TESTS"] == "1"))
func agreesWithNetstat() throws {
    let device = try JuistClient().status(figures: false).device
    let ours = try #require(InterfaceCounters.read(device))
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
    p.arguments = ["-I", device, "-b"]
    let pipe = Pipe()
    p.standardOutput = pipe
    try p.run()
    p.waitUntilExit()
    let line = try #require(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(separator: "\n").first { $0.contains("<Link#") })
    let cols = line.split(separator: " ")
    let ibytes = try #require(UInt64(cols[cols.count - 5])), obytes = try #require(UInt64(cols[cols.count - 2]))
    // A keepalive may pass between the two reads.
    #expect(ours.rxBytes <= ibytes && ibytes - ours.rxBytes < 10_000)
    #expect(ours.txBytes <= obytes && obytes - ours.txBytes < 10_000)
}
