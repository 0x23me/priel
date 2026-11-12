import Foundation
import Testing

@testable import JuistKit

private func hex(_ s: String) -> Data {
    var d = Data()
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        d.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return d
}

// Vectors from RFC 8949 appendix A.
@Test(arguments: [
    ("00", CBOR.unsigned(0)), ("17", .unsigned(23)), ("1818", .unsigned(24)), ("1903e8", .unsigned(1000)),
    ("1a000f4240", .unsigned(1_000_000)), ("1b000000e8d4a51000", .unsigned(1_000_000_000_000)),
    ("20", CBOR(-1)), ("3863", CBOR(-100)), ("3903e7", CBOR(-1000)),
    ("40", .bytes(Data())), ("4401020304", .bytes(Data([1, 2, 3, 4]))),
    ("60", .text("")), ("6161", .text("a")), ("6449455446", .text("IETF")), ("62c3bc", .text("\u{fc}")),
    ("80", .array([])), ("83010203", .array([.unsigned(1), .unsigned(2), .unsigned(3)])),
    ("8301820203820405", .array([.unsigned(1), .array([.unsigned(2), .unsigned(3)]), .array([.unsigned(4), .unsigned(5)])])),
    ("a0", .map([:])), ("a201020304", .map([.unsigned(1): .unsigned(2), .unsigned(3): .unsigned(4)])),
    ("a26161016162820203", .map([.text("a"): .unsigned(1), .text("b"): .array([.unsigned(2), .unsigned(3)])])),
    ("c074323031332d30332d32315432303a30343a30305a", .tagged(0, .text("2013-03-21T20:04:00Z"))),
    ("f4", .bool(false)), ("f5", .bool(true)), ("f6", .null), ("f7", .undefined),
    ("f93c00", .float(1.0)), ("f9c400", .float(-4.0)), ("fa47c35000", .float(100_000.0)), ("fb3ff199999999999a", .float(1.1)),
])
func decodesTheRFCVectors(_ encoded: String, _ want: CBOR) throws {
    #expect(try CBOR.decode(hex(encoded)) == want)
}

@Test func encodesCanonically() {
    // Integer keys in order, the one-byte ones before those with a length byte.
    let request = CBOR.map([.unsigned(100): .bool(true), .unsigned(31): .bytes(Data(count: 2)), .unsigned(1): .unsigned(1)])
    #expect(request.encoded() == hex("a30101181f4200001864f5"))
    #expect(CBOR(-1000).encoded() == hex("3903e7"))
    #expect(CBOR.unsigned(1_000_000_000_000).encoded() == hex("1b000000e8d4a51000"))
    #expect(CBOR.text("IETF").encoded() == hex("6449455446"))
}

@Test func roundTrips() throws {
    let value = CBOR.map([
        .unsigned(1): .array([.text("x"), .bytes(Data([0, 255])), .bool(false), .null, CBOR(-7)]),
        .unsigned(500): .map([.unsigned(2): .unsigned(UInt64.max)]),
    ])
    #expect(try CBOR.decode(value.encoded()) == value)
}

@Test func readsMapsByIntegerKey() throws {
    let v = try CBOR.decode(hex("a2016161181f182a"))
    #expect(v[1]?.string == "a")
    #expect(v[31]?.int == 42)
    #expect(v[2] == nil)
    #expect(CBOR.unsigned(1)[1] == nil)
}

@Test(arguments: [
    ("", CBORError.truncated), ("18", .truncated), ("62c3", .truncated), ("8301", .truncated),
    ("0000", .trailingBytes), ("5f", .unsupported("indefinite length")), ("1c", .unsupported("additional information 28")),
    ("62c328", .invalidUTF8), ("f0", .unsupported("simple value 16")),
])
func refusesMalformedInput(_ encoded: String, _ want: CBORError) {
    #expect(throws: want) { try CBOR.decode(hex(encoded)) }
}

@Test func refusesAHugeCountWithoutAllocating() {
    #expect(throws: CBORError.truncated) { try CBOR.decode(hex("9bffffffffffffffff")) }
}

@Test func refusesDeepNesting() {
    #expect(throws: CBORError.tooDeep) { try CBOR.decode(Data(repeating: 0x81, count: 40) + Data([0])) }
}
