// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "IssueTalkCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "IssueTalkCore", targets: ["IssueTalkCore"])],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.6.0")
  ],
  targets: [
    .target(
      name: "IssueTalkCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
    .testTarget(
      name: "IssueTalkCoreTests", dependencies: ["IssueTalkCore"], resources: [.process("Fixtures")]
    ),
  ]
)
