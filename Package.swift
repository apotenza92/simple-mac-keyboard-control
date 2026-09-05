// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "KeyControl",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "KeyControl", targets: ["KeyControl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
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
            dependencies: ["KeyControlCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "KeyControlCoreTests", dependencies: ["KeyControlCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
