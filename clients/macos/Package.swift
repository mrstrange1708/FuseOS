// swift-tools-version: 5.9
import PackageDescription

// Split deliberately: `FuseOSCore` holds the logic (crypto, LAN transport, clipboard
// rules, control-plane client) with no SwiftUI in it, so it can be unit-tested. `FuseOS`
// is the thin SwiftUI app on top. An executable target cannot be imported by a test
// target, which is why the logic had to move out to be testable at all.
let package = Package(
    name: "FuseOS",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Runtime only. The bindings themselves are generated from ../../proto by
        // build-app.sh, which needs `protoc` and `protoc-gen-swift` on PATH
        // (brew install protobuf swift-protobuf).
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0"),
    ],
    targets: [
        .target(
            name: "FuseOSCore",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")],
            path: "Sources/FuseOSCore",
        ),
        .executableTarget(
            name: "FuseOS",
            dependencies: ["FuseOSCore"],
            path: "Sources/FuseOS",
        ),
        .testTarget(
            name: "FuseOSCoreTests",
            dependencies: ["FuseOSCore"],
            path: "Tests/FuseOSCoreTests",
        ),
    ],
)
