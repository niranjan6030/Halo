// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Halo", targets: ["Halo"]),
        // Loaded by System Settings as Halo.prefPane (assembled by Scripts/build-app.sh).
        .library(name: "HaloPane", type: .dynamic, targets: ["HaloPane"]),
    ],
    targets: [
        // Preferences and the settings screen, shared by the app and the System Settings pane.
        .target(name: "HaloCore"),
        .executableTarget(name: "Halo", dependencies: ["HaloCore"]),
        .target(name: "HaloPane", dependencies: ["HaloCore"]),
        // The now-playing bridge in Helper/ is not a SwiftPM target: it is a dylib
        // that /usr/bin/perl loads, so Scripts/build-app.sh compiles it with clang.
    ],
    // Swift 5 language mode: everything UI-facing is main-actor bound already, and
    // the C callback APIs used here (CoreAudio, IOKit, CGEventTap) predate strict concurrency.
    swiftLanguageModes: [.v5]
)
