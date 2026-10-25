// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Chopstix",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Chopstix"),
        .testTarget(name: "ChopstixTests", dependencies: ["Chopstix"]),
    ],
    swiftLanguageModes: [.v5]
)
