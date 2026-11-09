// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HalfsiesKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "HalfsiesCore", targets: ["HalfsiesCore"]),
        .library(name: "HalfsiesBLE", targets: ["HalfsiesBLE"]),
        .library(name: "HalfsiesBattery", targets: ["HalfsiesBattery"]),
        .library(name: "HalfsiesUI", targets: ["HalfsiesUI"]),
    ],
    targets: [
        // Transport-agnostic keyboard model and pure logic. Foundation only.
        .target(name: "HalfsiesCore"),
        // The only module that imports CoreBluetooth.
        .target(name: "HalfsiesBLE", dependencies: ["HalfsiesCore"]),
        // Battery feature: observable state and settings for the UI.
        .target(name: "HalfsiesBattery", dependencies: ["HalfsiesCore"]),
        // SwiftUI views for the menu bar panel and settings.
        .target(name: "HalfsiesUI", dependencies: ["HalfsiesBattery"]),
        .testTarget(name: "HalfsiesCoreTests", dependencies: ["HalfsiesCore"]),
        .testTarget(name: "HalfsiesBatteryTests", dependencies: ["HalfsiesBattery"]),
    ]
)
