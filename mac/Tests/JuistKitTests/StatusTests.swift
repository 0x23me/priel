import Foundation
import Testing

@testable import JuistKit

func fixture(_ name: String) throws -> CBOR {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "cbor", subdirectory: "Fixtures"))
    return try CBOR.decode(Data(contentsOf: url))
}

/// The status of the patched 0.27.1 daemon on a laptop at home, before the
/// figures were added, read as its operator.
@Test func decodesTheOperatorsStatus() throws {
    let response = try fixture("stock-operator")
    let s = Status(cbor: try #require(response[2]))
    #expect(s.networkName == "lab")
    #expect(s.selfName == "laptop-01")
    #expect(s.inNetwork)
    #expect(s.canOperate)
    #expect(s.device == "utun9")
    #expect(s.addresses.contains("198.18.68.2/32"))
    #expect(s.addresses.contains { $0.hasPrefix("fd12:3456:789a:20fc:") })
    let gate = try #require(s.devices.first { $0.name == "gate" })
    #expect(gate.subnets == ["10.99.0.0/16"])
    #expect(s.reach.count == 1)
    let reach = try #require(s.reach.first)
    #expect(reach.identity == gate.identity)
    #expect(reach.live && reach.direct)
    #expect(reach.handshake == nil && reach.rxBytes == 0)
    #expect(s.subnets == [{
        var r = SubnetRoute()
        r.prefix = "10.99.0.0/16"
        r.routerName = "gate"
        r.why = "this device is on a network inside it"
        return r
    }()])
    #expect(s.startError.isEmpty && s.alarm.isEmpty)
}

@Test func decodesPrefixes() {
    #expect(Prefix.string(Data([10, 99, 0, 0, 16])) == "10.99.0.0/16")
    #expect(Prefix.string(Data([0xfd, 0x12] + [UInt8](repeating: 0, count: 13) + [1, 128])) == "fd12::1/128")
    #expect(Prefix.string(Data([1, 2, 3])) == nil)
}

@Test func decodesTheFigures() {
    let r = PeerReach(cbor: .map([CBOR(2): .bool(true), CBOR(100): CBOR(1_700_000_000), CBOR(101): .unsigned(4096), CBOR(102): .unsigned(512)]))
    #expect(r.live)
    #expect(r.handshake == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(r.rxBytes == 4096 && r.txBytes == 512)
}

/// The same device after the figures patch, asked with `Request.Figures`.
@Test func decodesTheOperatorsFigures() throws {
    let s = Status(cbor: try #require(try fixture("operator-figures")[2]))
    let reach = try #require(s.reach.first)
    #expect(reach.live && reach.direct)
    let handshake = try #require(reach.handshake)
    #expect(handshake > Date(timeIntervalSince1970: 1_762_000_000))
    #expect(reach.rxBytes > 0 && reach.txBytes > 0)
}
