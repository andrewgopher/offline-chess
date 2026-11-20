// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OfflineChess",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OfflineChess", targets: ["OfflineChess"]),
        .library(name: "ChessCore", targets: ["ChessCore"]),
    ],
    targets: [
        // Pure-Swift chess rules, PGN, clocks and the two-player match protocol.
        // Depends only on Foundation, so it is unit-testable anywhere.
        .target(name: "ChessCore"),
        // Nearby-Mac discovery and a 1:1 link over MultipeerConnectivity (peer-to-peer Wi-Fi).
        .target(name: "PeerKit", dependencies: ["ChessCore"]),
        // The macOS SwiftUI app: UI, game flow, persistence.
        .executableTarget(name: "OfflineChess", dependencies: ["ChessCore", "PeerKit"]),
        // Headless two-process check of PeerKit + the match protocol (used in CI).
        .executableTarget(name: "PeerSmokeTest", dependencies: ["ChessCore", "PeerKit"]),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"]),
    ]
)
