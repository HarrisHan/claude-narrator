// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "ClaudeNarrator",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "ClaudeNarrator", targets: ["ClaudeNarrator"])
  ],
  targets: [
    .executableTarget(
      name: "ClaudeNarrator",
      linkerSettings: [
        .linkedFramework("AVFAudio"),
        .linkedFramework("Carbon"),
        .linkedFramework("Network"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
    .testTarget(
      name: "ClaudeNarratorTests",
      dependencies: ["ClaudeNarrator"]
    ),
  ]
)
