// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "typesafe-sdk-swift",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
    .tvOS(.v16),
    .watchOS(.v9),
  ],
  products: [
    .library(name: "TypeSafe", targets: ["TypeSafe"])
  ],
  targets: [
    .target(name: "TypeSafe"),
    .testTarget(name: "TypeSafeTests", dependencies: ["TypeSafe"]),
  ]
)
