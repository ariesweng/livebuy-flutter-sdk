// swift-tools-version: 5.9
// Swift Package manifest for the `livebuy_flutter` iOS plugin.
//
// The iOS bridge (`Sources/livebuy_flutter/LivebuyPlugin.swift`) `import`s
// `LivebuySDK`, which is itself a Swift Package (it links the AmazonIVSPlayer
// binary XCFramework). CocoaPods cannot express a dependency on an SPM package,
// so this plugin uses Flutter's Swift Package Manager integration (enabled by
// default on current stable Flutter) and depends on the LivebuySDK package — SPM
// resolves LivebuySDK + its IVS binaryTarget for us.
//
// LivebuySDK source resolution:
//   • Flutter integrates a plugin's SPM package via a SYMLINK in the app's
//     ephemeral build dir, so a path RELATIVE to this manifest would resolve from
//     that ephemeral location (and depends on where the host app lives) — unusable
//     for a monorepo-local sibling package. So the local source is provided as an
//     ABSOLUTE path via the LIVEBUY_SDK_LOCAL_PATH env var.
//   • CI (flutter-bridge-build.yml) + local dev (example bootstrap) export
//     LIVEBUY_SDK_LOCAL_PATH=<repo>/ios to compile against monorepo source.
//   • Published consumers (no env var) resolve LivebuySDK from the distribution
//     repo over Git.
import PackageDescription

let livebuySDKDependency: Package.Dependency = {
    if let localPath = Context.environment["LIVEBUY_SDK_LOCAL_PATH"], !localPath.isEmpty {
        return .package(name: "LivebuySDK", path: localPath)
    }
    return .package(
        name: "LivebuySDK",
        url: "https://github.com/ariesweng/livebuy-ios-sdk.git",
        from: "4.0.0"
    )
}()

let package = Package(
    name: "livebuy_flutter",
    // Must be >= LivebuySDK's deployment target (.iOS(.v14)).
    platforms: [
        .iOS("14.0")
    ],
    products: [
        .library(name: "livebuy-flutter", targets: ["livebuy_flutter"])
    ],
    dependencies: [
        // Flutter-injected framework (provides the `Flutter` module). Resolved by
        // Flutter relative to the ephemeral symlink — keep as the template emits it.
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        livebuySDKDependency
    ],
    targets: [
        .target(
            name: "livebuy_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "LivebuySDK", package: "LivebuySDK")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
