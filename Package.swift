// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EffyWoWCompanion",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "EffyWoWCompanion", targets: ["EffyWoWCompanion"])],
    targets: [.executableTarget(name: "EffyWoWCompanion", resources: [.process("PetAssets")]), .testTarget(name: "EffyWoWCompanionTests", dependencies: ["EffyWoWCompanion"])]
)
