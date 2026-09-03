// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "KeyControl",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "KeyControl", targets: ["KeyControl"]),
    ],
    targets: [
        .target(
            name: "KeyControlCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "KeyControl",
            dependencies: ["KeyControlCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "KeyControlCoreTests", dependencies: ["KeyControlCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
