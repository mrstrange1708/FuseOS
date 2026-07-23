// swift-tools-version: 5.9
import PackageDescription

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
        .executableTarget(
            name: "FuseOS",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")],
            path: "Sources/FuseOS",
        ),
    ],
)
