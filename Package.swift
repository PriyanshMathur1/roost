// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Roost",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure layout and tiling state: no AppKit, fully testable.
        .target(name: "RoostCore"),
        // The menu-bar app: Accessibility window control, hotkeys, status item.
        .executableTarget(
            name: "Roost",
            dependencies: ["RoostCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // XCTest and Swift Testing need a full Xcode install, so the tests are a
        // plain executable: `swift run RoostCoreTests` exits non-zero on failure.
        .executableTarget(name: "RoostCoreTests", dependencies: ["RoostCore"], path: "Tests/RoostCoreTests"),
    ]
)
