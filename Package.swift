// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotesMini",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotesMini", targets: ["NotesMini"]),
        .library(name: "NotesMiniCore", targets: ["NotesMiniCore"]),
        .executable(name: "NotesMiniChecks", targets: ["NotesMiniChecks"]),
    ],
    targets: [
        // AppKit-heavy, main-thread codebase: Swift 5 language mode keeps strict-concurrency
        // diagnostics out of the way. CommandLineTools has no XCTest / swift-testing, so the
        // regression suite lives in the NotesMiniChecks executable instead.
        .target(name: "NotesMiniCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "NotesMini", dependencies: ["NotesMiniCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "NotesMiniChecks", dependencies: ["NotesMiniCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)