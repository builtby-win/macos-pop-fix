// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PopFix",
    platforms: [.macOS(.v13)],
    // mediaremote-adapter is not linked: build.sh builds its dylib + run.pl and bundles them; PopFix runs them under /usr/bin/perl.
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter", branch: "master"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [.executableTarget(name: "PopFix", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: "Sources/PopFix")]
)
