// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "IssueTalkCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "IssueTalkCore", targets: ["IssueTalkCore"])],
  targets: [
    .target(name: "IssueTalkCore"),
    .testTarget(name: "IssueTalkCoreTests", dependencies: ["IssueTalkCore"])
  ]
)
