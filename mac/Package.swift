// swift-tools-version: 6.0
import PackageDescription

// Priel uses JuistKit; nothing depends on Priel.
//   JuistKit   juistd's socket, its status, the tunnel's counters, the daemon's registration
//   Priel      the menu bar app
let package = Package(
    name: "priel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Priel", targets: ["Priel"]),
        .library(name: "JuistKit", targets: ["JuistKit"]),
    ],
    targets: [
        .target(name: "JuistKit"),
        .executableTarget(name: "Priel", dependencies: ["JuistKit"]),
        .testTarget(name: "JuistKitTests", dependencies: ["JuistKit"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
