// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VitraRadio",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "VitraRadio", targets: ["VitraRadio"])],
    targets: [.executableTarget(name: "VitraRadio")]
)
