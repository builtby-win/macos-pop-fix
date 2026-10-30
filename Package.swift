// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PopFix",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "PopFix", path: "Sources/PopFix")]
)
