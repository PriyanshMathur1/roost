// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tessera",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure layout and tiling state: no AppKit, fully testable.
        .target(name: "TesseraCore"),
        // The menu-bar app: Accessibility window control, hotkeys, status item.
        .executableTarget(
            name: "Tessera",
            dependencies: ["TesseraCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // XCTest and Swift Testing need a full Xcode install, so the tests are a
        // plain executable: `swift run TesseraCoreTests` exits non-zero on failure.
        .executableTarget(name: "TesseraCoreTests", dependencies: ["TesseraCore"], path: "Tests/TesseraCoreTests"),
    ]
)
