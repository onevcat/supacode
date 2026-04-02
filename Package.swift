// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ProwlCLI",
  platforms: [
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "ProwlCLIShared",
      targets: ["ProwlCLIShared"]
    ),
    .executable(
      name: "prowl",
      targets: ["prowl"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "ProwlCLIShared",
      path: "supacode/CLIService/Shared"
    ),
    .executableTarget(
      name: "prowl",
      dependencies: [
        "ProwlCLIShared",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "ProwlCLI"
    ),
    .testTarget(
      name: "ProwlCLITests",
      dependencies: [
        "ProwlCLIShared",
        "prowl",
      ],
      path: "ProwlCLITests"
    ),
  ]
)
