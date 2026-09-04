#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint livebuy_flutter.podspec` to validate before publishing.
#
# This podspec is the CocoaPods-front-end counterpart to
# `livebuy_flutter/Package.swift` (Swift Package Manager). Both manifests build
# the SAME source tree — `livebuy_flutter/Sources/livebuy_flutter/**/*.swift` —
# so a host app can integrate `livebuy_flutter` via either Darwin dependency
# manager. See openspec/changes/add-flutter-plugin-ios-podspec/design.md for
# the rationale (mirrors Flutter's own `plugin_darwin_spm` template shape).
#
Pod::Spec.new do |s|
  s.name             = 'livebuy_flutter'
  s.version          = '2.0.1'
  s.summary          = 'Flutter plugin for Livebuy live-shopping SDK (iOS & Android).'
  s.description      = <<-DESC
Flutter plugin for Livebuy live-shopping SDK (iOS & Android).
                       DESC
  s.homepage         = 'https://github.com/livebuy/livebuy-sdk/tree/main/flutter'
  s.license          = { :type => 'UNLICENSED', :text => 'Proprietary — Livebuy. All rights reserved.' }
  s.author           = { 'Livebuy' => 'team@livebuy.tv' }
  s.source           = { :path => '.' }

  # Same source tree as the SwiftPM target in livebuy_flutter/Package.swift —
  # no forked / duplicated Swift source between the two manifests.
  s.source_files = 'livebuy_flutter/Sources/livebuy_flutter/**/*.swift'

  # iOS-only, matching flutter/pubspec.yaml (no `macos` platform key) and
  # Package.swift's `platforms: [.iOS("14.0")]`.
  s.ios.deployment_target = '14.0'

  # Standard Flutter plugin requirement, provides the `Flutter` module.
  # (SwiftPM gets the equivalent via the `FlutterFramework` package dependency
  # already declared in Package.swift.)
  s.dependency 'Flutter'

  # ───────────────────────────────────────────────────────────────────────────
  # Core headless SDK — mirrors react-native/livebuy-react-native.podspec's
  # DECIDED plan B (ios-core-cocoapods-podspec-distribution).
  #
  # `LivebuyPlugin.swift` `import LivebuySDK` and calls `Livebuy.configure(...)`,
  # so this pod must link the core `LivebuySDK` XCFramework to fully COMPILE.
  # `~> 4.0` = CocoaPods optimistic operator, [4.0.0, 5.0.0) — aligned to the
  # major boundary introduced by the 2026-07-16 brand-casing rename (commit
  # c140f4bf), same bound the RN bridge podspec pins.
  #
  # RESOLUTION — the consumer's Podfile MUST make the `LivebuySDK` pod findable
  # (exactly like SwiftPM consumers add `.package(url:)`). Pick ONE, same three
  # options react-native/livebuy-react-native.podspec documents:
  #   • spec repo:
  #       source "https://github.com/ariesweng/livebuy-ios-podspecs.git"
  #       source "https://cdn.cocoapods.org"
  #   • release-attached podspec:
  #       pod "LivebuySDK", :podspec =>
  #         "https://github.com/ariesweng/livebuy-ios-sdk/releases/download/<current release tag>/LivebuySDK.podspec"
  #   • local dev (monorepo checkout):
  #       pod "LivebuySDK", :podspec => "<repo>/livebuy-ios-sdk/LivebuySDK.podspec"
  #
  # Without one of these, `pod install` stops with "unable to find a
  # specification for LivebuySDK" — the correct, expected plan-B behaviour.
  # ───────────────────────────────────────────────────────────────────────────
  s.dependency 'LivebuySDK', '~> 4.0'

  # Flutter.framework does not contain an i386 slice, which is specific to iOS.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }

  s.swift_version = '5.9'

  # CocoaPods/Xcode 15+ privacy manifest packaging. Same PrivacyInfo.xcprivacy
  # file the SwiftPM target already ships via `.process("PrivacyInfo.xcprivacy")`
  # in Package.swift — this just adds the CocoaPods-specific packaging
  # instruction, it does not duplicate or diverge the content.
  s.resource_bundles = { 'livebuy_flutter_privacy' => ['livebuy_flutter/Sources/livebuy_flutter/PrivacyInfo.xcprivacy'] }
end
