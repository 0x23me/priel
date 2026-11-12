import Foundation
import Testing

@testable import JuistKit

private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

private let zero32 = String(repeating: "00", count: 32)

/// The bytes Go's juist encodes for these requests (encode(&Request{...})).
@Test func encodesRequestsAsJuistDoes() {
    #expect(hex(JuistClient.request(command: 1).encoded()) == "a301010f5820\(zero32)181f5820\(zero32)")
    #expect(hex(JuistClient.request(command: 1, figures: true).encoded()) == "a401010f5820\(zero32)181f5820\(zero32)1864f5")
}

@Test func aMissingSocketIsNotRunning() {
    let client = JuistClient(socketPath: "/var/run/juist/none-here.sock")
    #expect(throws: JuistError.notRunning) { try client.status(figures: false) }
}

/// A one-shot server on a socket in a temporary folder that reads one framed
/// request and writes answer.
private final class FakeDaemon: @unchecked Sendable {
    let path: String
    private let fd: Int32
    private(set) var received = Data()
    private let done = DispatchSemaphore(value: 0)

    init(answer: CBOR) throws {
        path = "/tmp/jb-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 1) == 0 else { throw JuistError.io("fake daemon") }
        Thread.detachNewThread { [self] in
            let c = accept(fd, nil, nil)
            var head = [UInt8](repeating: 0, count: 4)
            _ = read(c, &head, 4)
            let n = head.reduce(0) { $0 << 8 | Int($1) }
            var body = [UInt8](repeating: 0, count: n)
            var off = 0
            while off < n { off += read(c, &body[off], n - off) }
            received = Data(body)
            let out = answer.encoded()
            var frame = withUnsafeBytes(of: UInt32(out.count).bigEndian) { Data($0) }
            frame.append(out)
            frame.withUnsafeBytes { _ = write(c, $0.baseAddress!, $0.count) }
            close(c)
            done.signal()
        }
    }

    func wait() { done.wait() }

    deinit {
        close(fd)
        unlink(path)
    }
}

@Test func readsTheStatusOverTheSocket() throws {
    let daemon = try FakeDaemon(answer: .map([CBOR(2): .map([CBOR(4): .text("lab"), CBOR(60): .text("utun9")])]))
    let s = try JuistClient(socketPath: daemon.path).status(figures: true)
    daemon.wait()
    #expect(s.networkName == "lab" && s.device == "utun9")
    #expect(try CBOR.decode(daemon.received)[100] == .bool(true))
}

@Test func anErrorAnswerThrows() throws {
    let daemon = try FakeDaemon(answer: .map([CBOR(1): .text("ipc: unknown field")]))
    #expect(throws: JuistError.daemon("ipc: unknown field")) { try JuistClient(socketPath: daemon.path).status(figures: true) }
    daemon.wait()
}

@Test func pingsReturnSeconds() throws {
    let daemon = try FakeDaemon(answer: .map([CBOR(14): .map([CBOR(1): CBOR(2500)])]))
    let member = Data(repeating: 7, count: 32)
    let rtt = try JuistClient(socketPath: daemon.path).ping(member)
    daemon.wait()
    #expect(rtt == 0.0025)
    let req = try CBOR.decode(daemon.received)
    #expect(req[1]?.int == 24 && req[31]?.data == member)
}

/// The real juistd on this Mac, when JUIST_LIVE_TESTS=1.
@Test(.enabled(if: ProcessInfo.processInfo.environment["JUIST_LIVE_TESTS"] == "1"))
func readsTheLiveDaemon() throws {
    let s = try JuistClient().status(figures: false)
    #expect(!s.networkName.isEmpty)
}
