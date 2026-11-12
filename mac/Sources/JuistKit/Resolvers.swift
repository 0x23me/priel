import Foundation

/// A domain whose lookups go to one nameserver: a line of Priel's list, or a
/// file in /etc/resolver.
public struct Resolver: Equatable, Hashable, Sendable {
    public var domain: String
    public var server: String

    public init(domain: String, server: String) {
        self.domain = domain
        self.server = server
    }

    /// The list priel-dns turns into /etc/resolver files while juistd runs.
    public static let listPath = "/etc/priel/resolvers"
    public static let systemDirectory = "/etc/resolver"
    /// The first line of each file priel-dns writes.
    public static let mark = "# Written by Priel while juist is on, removed when it stops. Edit the list in Priel."

    /// Priel's list: "DOMAIN NAMESERVER" lines, # for comments.
    public static func list(_ text: String) -> [Resolver] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.count >= 2, !words[0].hasPrefix("#") else { return nil }
            return Resolver(domain: String(words[0]), server: String(words[1]))
        }
    }

    /// One /etc/resolver file: the domain is its name, the server its first nameserver line.
    /// ours is whether priel-dns wrote it.
    public static func file(domain: String, _ text: String) -> (resolver: Resolver, ours: Bool)? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let words = line.split(whereSeparator: \.isWhitespace)
            if words.count >= 2 && words[0] == "nameserver" {
                return (Resolver(domain: domain, server: String(words[1])), lines.first == mark)
            }
        }
        return nil
    }

    /// The files in a resolver directory, as file reads them.
    public static func files(in directory: String = systemDirectory) -> [(resolver: Resolver, ours: Bool)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.sorted().compactMap { name in
            guard !name.hasPrefix("."), let text = try? String(contentsOfFile: directory + "/" + name, encoding: .utf8) else { return nil }
            return file(domain: name, text)
        }
    }

    /// Whether a domain and server are ones priel-dns takes: a hostname, and an IP address.
    public var valid: Bool {
        let host = domain.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        return host && !domain.isEmpty && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !domain.contains("..")
            && IPAddress(server) != nil
    }

    /// Whether the server lies in prefix, as "10.23.0.0/16".
    public func server(in prefix: String) -> Bool {
        let parts = prefix.split(separator: "/")
        guard parts.count == 2, let net = IPAddress(String(parts[0])), let bits = Int(parts[1]),
              let ip = IPAddress(server), ip.bytes.count == net.bytes.count, bits >= 0, bits <= ip.bytes.count * 8
        else { return false }
        for i in 0..<ip.bytes.count {
            let take = min(max(bits - i * 8, 0), 8)
            let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - take))
            if ip.bytes[i] & mask != net.bytes[i] & mask { return false }
        }
        return true
    }
}

/// An IPv4 or IPv6 address as its bytes.
struct IPAddress {
    var bytes: [UInt8]

    init?(_ text: String) {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            bytes = withUnsafeBytes(of: v4) { Array($0) }
        } else if inet_pton(AF_INET6, text, &v6) == 1 {
            bytes = withUnsafeBytes(of: v6) { Array($0) }
        } else {
            return nil
        }
    }
}
