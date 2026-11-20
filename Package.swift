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
        // The macOS SwiftUI app: UI, MultipeerConnectivity transport, persistence.
        .executableTarget(name: "OfflineChess", dependencies: ["ChessCore"]),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"]),
    ]
)
