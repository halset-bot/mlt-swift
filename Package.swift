// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MLTEncoder",
    // Matching swift-geo's minimum platform requirement.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MLTEncoder", targets: ["MLTEncoder"]),
        .executable(name: "MLTEncoderTests", targets: ["MLTEncoderTests"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ElectronicChartCentre/swift-geo",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "MLTEncoder",
            dependencies: [
                .product(name: "SwiftGeo", package: "swift-geo"),
            ]
        ),
        .executableTarget(
            name: "MLTEncoderTests",
            dependencies: ["MLTEncoder"]
        ),
    ]
)
