import Foundation

/// A CBOR value (RFC 8949), as much of it as juistd's socket uses: no
/// indefinite lengths, which juistd forbids, and no simple values beyond
/// false, true, null and undefined.
public indirect enum CBOR: Hashable, Sendable {
    case unsigned(UInt64)
    /// The integer -1 - n.
    case negative(UInt64)
    case bytes(Data)
    case text(String)
    case array([CBOR])
    case map([CBOR: CBOR])
    case tagged(UInt64, CBOR)
    case bool(Bool)
    case null
    case undefined
    case float(Double)

    public init(_ value: Int) {
        self = value >= 0 ? .unsigned(UInt64(value)) : .negative(UInt64(-1 - value))
    }
}

public enum CBORError: Error, Equatable {
    case truncated
    case trailingBytes
    case tooDeep
    case invalidUTF8
    case unsupported(String)
}

// MARK: Reading values

extension CBOR {
    /// The value under an integer key of a map, nil where there is none or
    /// this is no map.
    public subscript(_ key: Int) -> CBOR? {
        guard case .map(let m) = self else { return nil }
        return m[CBOR(key)]
    }

    public var int: Int? {
        switch self {
        case .unsigned(let n): n <= UInt64(Int.max) ? Int(n) : nil
        case .negative(let n): n < UInt64(Int.max) ? -1 - Int(n) : nil
        default: nil
        }
    }

    public var uint64: UInt64? {
        if case .unsigned(let n) = self { return n }
        return nil
    }

    public var string: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    public var data: Data? {
        if case .bytes(let d) = self { return d }
        return nil
    }

    public var array: [CBOR]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

// MARK: Decoding

extension CBOR {
    /// The single value data holds; trailing bytes are an error.
    public static func decode(_ data: Data, maxDepth: Int = 32) throws -> CBOR {
        var reader = Reader(bytes: [UInt8](data), maxDepth: maxDepth)
        let value = try reader.value(depth: 0)
        guard reader.pos == reader.bytes.count else { throw CBORError.trailingBytes }
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        let maxDepth: Int
        var pos = 0

        mutating func byte() throws -> UInt8 {
            guard pos < bytes.count else { throw CBORError.truncated }
            defer { pos += 1 }
            return bytes[pos]
        }

        mutating func take(_ n: UInt64) throws -> ArraySlice<UInt8> {
            guard n <= UInt64(bytes.count - pos) else { throw CBORError.truncated }
            defer { pos += Int(n) }
            return bytes[pos..<pos + Int(n)]
        }

        mutating func uint(_ size: Int) throws -> UInt64 {
            try take(UInt64(size)).reduce(0) { $0 << 8 | UInt64($1) }
        }

        /// The head's argument for additional information info.
        mutating func argument(_ info: UInt8) throws -> UInt64 {
            switch info {
            case 0..<24: UInt64(info)
            case 24: try uint(1)
            case 25: try uint(2)
            case 26: try uint(4)
            case 27: try uint(8)
            case 31: throw CBORError.unsupported("indefinite length")
            default: throw CBORError.unsupported("additional information \(info)")
            }
        }

        /// A count of items still to read, each at least one byte long.
        mutating func count(_ info: UInt8) throws -> Int {
            let n = try argument(info)
            guard n <= UInt64(bytes.count - pos) else { throw CBORError.truncated }
            return Int(n)
        }

        mutating func value(depth: Int) throws -> CBOR {
            guard depth <= maxDepth else { throw CBORError.tooDeep }
            let head = try byte()
            let major = head >> 5, info = head & 0x1f
            switch major {
            case 0:
                return .unsigned(try argument(info))
            case 1:
                return .negative(try argument(info))
            case 2:
                return .bytes(Data(try take(try argument(info))))
            case 3:
                guard let s = String(bytes: try take(try argument(info)), encoding: .utf8) else { throw CBORError.invalidUTF8 }
                return .text(s)
            case 4:
                let n = try count(info)
                var items: [CBOR] = []
                items.reserveCapacity(n)
                for _ in 0..<n { items.append(try value(depth: depth + 1)) }
                return .array(items)
            case 5:
                let n = try count(info)
                var pairs: [CBOR: CBOR] = [:]
                for _ in 0..<n {
                    let key = try value(depth: depth + 1)
                    pairs[key] = try value(depth: depth + 1)
                }
                return .map(pairs)
            case 6:
                let tag = try argument(info)
                return .tagged(tag, try value(depth: depth + 1))
            default:
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                case 23: return .undefined
                case 25: return .float(Self.half(UInt16(try uint(2))))
                case 26: return .float(Double(Float(bitPattern: UInt32(try uint(4)))))
                case 27: return .float(Double(bitPattern: try uint(8)))
                default: throw CBORError.unsupported("simple value \(info)")
                }
            }
        }

        static func half(_ bits: UInt16) -> Double {
            let exponent = Int(bits >> 10 & 0x1f), mantissa = Double(bits & 0x3ff)
            let magnitude: Double = switch exponent {
            case 0: mantissa * pow(2, -24)
            case 31: mantissa == 0 ? .infinity : .nan
            default: (1 + mantissa / 1024) * pow(2, Double(exponent - 15))
            }
            return bits & 0x8000 != 0 ? -magnitude : magnitude
        }
    }
}

// MARK: Encoding

extension CBOR {
    /// The canonical encoding juistd expects (CTAP2): shortest heads, map
    /// keys sorted by their encoding, shorter first.
    public func encoded() -> Data {
        var out = Data()
        encode(into: &out)
        return out
    }

    private func encode(into out: inout Data) {
        switch self {
        case .unsigned(let n): Self.head(0, n, into: &out)
        case .negative(let n): Self.head(1, n, into: &out)
        case .bytes(let d):
            Self.head(2, UInt64(d.count), into: &out)
            out.append(d)
        case .text(let s):
            let utf8 = Data(s.utf8)
            Self.head(3, UInt64(utf8.count), into: &out)
            out.append(utf8)
        case .array(let items):
            Self.head(4, UInt64(items.count), into: &out)
            for item in items { item.encode(into: &out) }
        case .map(let pairs):
            Self.head(5, UInt64(pairs.count), into: &out)
            let sorted = pairs.map { (key: $0.key.encoded(), value: $0.value) }.sorted {
                $0.key.count != $1.key.count ? $0.key.count < $1.key.count : $0.key.lexicographicallyPrecedes($1.key)
            }
            for pair in sorted {
                out.append(pair.key)
                pair.value.encode(into: &out)
            }
        case .tagged(let tag, let value):
            Self.head(6, tag, into: &out)
            value.encode(into: &out)
        case .bool(let b): out.append(b ? 0xf5 : 0xf4)
        case .null: out.append(0xf6)
        case .undefined: out.append(0xf7)
        case .float(let d):
            out.append(0xfb)
            withUnsafeBytes(of: d.bitPattern.bigEndian) { out.append(contentsOf: $0) }
        }
    }

    private static func head(_ major: UInt8, _ n: UInt64, into out: inout Data) {
        let m = major << 5
        switch n {
        case 0..<24: out.append(m | UInt8(n))
        case 24...0xff: out.append(contentsOf: [m | 24, UInt8(n)])
        case 0x100...0xffff: out.append(m | 25); withUnsafeBytes(of: UInt16(n).bigEndian) { out.append(contentsOf: $0) }
        case 0x10000...0xffff_ffff: out.append(m | 26); withUnsafeBytes(of: UInt32(n).bigEndian) { out.append(contentsOf: $0) }
        default: out.append(m | 27); withUnsafeBytes(of: n.bigEndian) { out.append(contentsOf: $0) }
        }
    }
}
