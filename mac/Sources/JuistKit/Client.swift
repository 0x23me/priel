import Foundation

public enum JuistError: Error, Equatable, LocalizedError {
    /// No juistd listens on the socket.
    case notRunning
    /// juistd answered with an error.
    case daemon(String)
    case io(String)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning: "juistd is not running"
        case .daemon(let s): s
        case .io(let s): "talking to juistd: \(s)"
        case .malformed(let s): "juistd's answer: \(s)"
        }
    }
}

/// One request and its answer over juistd's socket. Each call dials anew, as
/// `juist` does: juistd restarting between calls costs nothing.
public struct JuistClient: Sendable {
    public static let systemSocket = "/var/run/juist/juistd.sock"
    /// Answers are a few kilobytes; juist allows itself 16 MiB.
    static let maxResponse = 16 << 20

    public var socketPath: String

    public init(socketPath: String = JuistClient.systemSocket) {
        self.socketPath = socketPath
    }

    /// The status; figures asks for the macOS patch's per-peer handshake and
    /// traffic, which a juistd without the patch refuses.
    public func status(figures: Bool) throws -> Status {
        let response = try call(Self.request(command: 1, figures: figures))
        guard let status = response[2] else { throw JuistError.malformed("no status") }
        return Status(cbor: status)
    }

    /// The round trip to member, through the tunnel. juistd answers it to
    /// the device's operator alone.
    public func ping(_ member: Data, timeout: TimeInterval = 5) throws -> TimeInterval {
        let response = try call(Self.request(command: 24, ping: member), timeout: timeout)
        guard let ping = response[14] else { throw JuistError.malformed("no ping") }
        if let err = ping[2]?.string, !err.isEmpty { throw JuistError.daemon(err) }
        return TimeInterval(ping[1]?.int ?? 0) / 1_000_000
    }

    /// A request as juistd decodes it canonically: the two identity fields
    /// (15, the exit node, and 31, the member to ping) are written even when
    /// zero, as Go writes a fixed-size array.
    static func request(command: Int, ping: Data = Data(count: 32), figures: Bool = false) -> CBOR {
        var fields: [CBOR: CBOR] = [
            CBOR(1): CBOR(command),
            CBOR(15): .bytes(Data(count: 32)),
            CBOR(31): .bytes(ping),
        ]
        if figures { fields[CBOR(100)] = .bool(true) }
        return .map(fields)
    }

    /// Sends request and returns the answer's map; an answer carrying an
    /// error (key 1) throws it.
    public func call(_ request: CBOR, timeout: TimeInterval = 3) throws -> CBOR {
        let fd = try connect(timeout: timeout)
        defer { close(fd) }
        let body = request.encoded()
        var frame = Data()
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        try writeAll(fd, frame)
        let length = try readExactly(fd, 4).reduce(0) { $0 << 8 | Int($1) }
        guard length <= Self.maxResponse else { throw JuistError.malformed("\(length) bytes") }
        let response: CBOR
        do {
            response = try CBOR.decode(readExactly(fd, length))
        } catch {
            throw JuistError.malformed("\(error)")
        }
        if let err = response[1]?.string, !err.isEmpty { throw JuistError.daemon(err) }
        return response
    }

    private func connect(timeout: TimeInterval) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw JuistError.io(String(cString: strerror(errno))) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8)
        guard path.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw JuistError.io("socket path too long")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: path) }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if ok != 0 {
            let e = errno
            close(fd)
            if e == ENOENT || e == ECONNREFUSED { throw JuistError.notRunning }
            throw JuistError.io(String(cString: strerror(e)))
        }
        return fd
    }

    private func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { buf in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw JuistError.io(String(cString: strerror(errno)))
                }
                off += n
            }
        }
    }

    private func readExactly(_ fd: Int32, _ count: Int) throws -> Data {
        var out = Data(count: count)
        var off = 0
        try out.withUnsafeMutableBytes { buf in
            while off < count {
                let n = read(fd, buf.baseAddress! + off, count - off)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw JuistError.io(errno == EAGAIN ? "no answer in time" : String(cString: strerror(errno)))
                }
                if n == 0 { throw JuistError.io("juistd closed the connection") }
                off += n
            }
        }
        return out
    }
}
