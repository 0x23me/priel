import Foundation
import Testing

@testable import JuistKit

@Test func theListSkipsCommentsAndBlankLines() {
    let list = Resolver.list("# DOMAIN NAMESERVER\nlab.example 10.99.0.1\n\n  # off\nv6.example fd12::1 extra\nbroken\n")
    #expect(list == [Resolver(domain: "lab.example", server: "10.99.0.1"), Resolver(domain: "v6.example", server: "fd12::1")])
}

@Test func aFileIsOursOnlyWithTheMark() {
    let ours = Resolver.file(domain: "lab.example", Resolver.mark + "\nnameserver 10.99.0.1\n")
    #expect(ours?.resolver == Resolver(domain: "lab.example", server: "10.99.0.1"))
    #expect(ours?.ours == true)
    let hand = Resolver.file(domain: "lab.example", "domain lab.example\nnameserver 10.99.0.1\n")
    #expect(hand?.ours == false)
    #expect(hand?.resolver.server == "10.99.0.1")
    #expect(Resolver.file(domain: "x", "search x\n") == nil)
}

@Test func serversInsideASubnet() {
    let r = Resolver(domain: "lab.example", server: "10.99.32.1")
    #expect(r.server(in: "10.99.0.0/16"))
    #expect(r.server(in: "10.99.32.0/20"))
    #expect(!r.server(in: "10.99.0.0/19"))
    #expect(!r.server(in: "fd12::/16"))
    #expect(Resolver(domain: "v6", server: "fd12:3456::1").server(in: "fd12:3456::/32"))
    #expect(!Resolver(domain: "v6", server: "fd12:3457::1").server(in: "fd12:3456::/32"))
    #expect(Resolver(domain: "any", server: "192.0.2.1").server(in: "0.0.0.0/0"))
}

@Test func validIsWhatPrielDNSTakes() {
    #expect(Resolver(domain: "b.lab.example", server: "10.99.1.1").valid)
    #expect(Resolver(domain: "lab.example", server: "fd12::1").valid)
    for (domain, server) in [("../etc", "10.0.0.1"), ("a/b", "10.0.0.1"), (".lead", "10.0.0.1"), ("ok.example", "10.0.0.1;rm"), ("ok.example", "host")] {
        #expect(!Resolver(domain: domain, server: server).valid)
    }
}
