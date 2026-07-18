// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "vidra_player",
  platforms: [
    .macOS("10.14")
  ],
  products: [
    .library(name: "vidra-player", targets: ["vidra_player"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "vidra_player",
      dependencies: [],
      resources: [
        .process("Resources/PrivacyInfo.xcprivacy")
      ]
    )
  ]
)
