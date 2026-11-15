// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PopFix",
    platforms: [.macOS(.v13)],
    // Not linked: build.sh builds its dylib + run.pl and bundles them; PopFix runs them under /usr/bin/perl.
    dependencies: [.package(url: "https://github.com/ejbills/mediaremote-adapter", branch: "master")],
    targets: [.executableTarget(name: "PopFix", path: "Sources/PopFix")]
)
