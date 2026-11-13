// swift-tools-version: 6.2
// Bundles the toolchain's built-in macro implementations (SwiftMacros,
// ObservationMacros, FoundationMacros) into ONE statically linked compiler
// plugin executable. A fully static (musl) compiler cannot dlopen() the usual
// lib*Macros.so plugins, but it can spawn an executable plugin
// (-load-plugin-executable <path>#<module>,<module>...).
import PackageDescription

let syntaxDeps: [Target.Dependency] = [
    .product(name: "SwiftSyntax", package: "swift-syntax"),
    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
    .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
    .product(name: "SwiftDiagnostics", package: "swift-syntax"),
    .product(name: "SwiftOperators", package: "swift-syntax"),
    .product(name: "SwiftParser", package: "swift-syntax"),
    .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
]

let package = Package(
    name: "swift-builtin-macros",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../src/swift-syntax")],
    targets: [
        .target(name: "SwiftMacros", dependencies: syntaxDeps,
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "ObservationMacros", dependencies: syntaxDeps,
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "FoundationMacros", dependencies: syntaxDeps,
                swiftSettings: [.swiftLanguageMode(.v5),
                                .define("FOUNDATION_MACROS_LIBRARY"),
                                .enableExperimentalFeature("AccessLevelOnImport")]),
        .target(name: "TestingMacros",
                dependencies: syntaxDeps + [.product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax")],
                swiftSettings: [
                    .swiftLanguageMode(.v6),
                    .enableExperimentalFeature("AvailabilityMacro=_uttypesAPI:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0"),
                    .enableExperimentalFeature("AvailabilityMacro=_clockAPI:macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0"),
                    .enableExperimentalFeature("AvailabilityMacro=_typedThrowsAPI:macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"),
                    .enableExperimentalFeature("AvailabilityMacro=_transferableAPI:macOS 15.2, iOS 18.2, watchOS 11.2, tvOS 18.2, visionOS 2.2"),
                    .enableExperimentalFeature("AvailabilityMacro=_castingWithNonCopyableGenerics:macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"),
                    .enableExperimentalFeature("AvailabilityMacro=_distantFuture:macOS 99.0, iOS 99.0, watchOS 99.0, tvOS 99.0, visionOS 99.0"),
                    .define("SWT_BUILDING_SWIFT_TESTING_CONTENT"),
                    .enableUpcomingFeature("ExistentialAny"),
                    .enableExperimentalFeature("AccessLevelOnImport"),
                    .enableUpcomingFeature("InternalImportsByDefault"),
                    .enableUpcomingFeature("MemberImportVisibility"),
                    .enableExperimentalFeature("Lifetimes"),
                    .enableUpcomingFeature("InferIsolatedConformances"),
                    .define("SWT_NO_SNAPSHOT_TYPES"),
                    .define("SWT_NO_FOUNDATION_FILE_COORDINATION"),
                    .define("SWT_NO_IMAGE_ATTACHMENTS"),
                ]),
        .executableTarget(
            name: "swift-builtin-macros",
            dependencies: ["SwiftMacros", "ObservationMacros", "FoundationMacros", "TestingMacros",
                           .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                           .product(name: "SwiftSyntaxMacros", package: "swift-syntax")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
