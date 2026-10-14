package tv.livebuy.flutter

import tv.livebuy.sdk.models.LBVodEndBehavior

// vod-end-loop-flutter-core — pure wire-string → native enum mapping for the `vodEndBehavior`
// argument of the `tv.livebuy/sdk` `configure` method call. Only the exact string "advance"
// selects ADVANCE; anything else (including a missing / null argument) falls back to LOOP — the
// native core default (Android core 4.28.0+). Mirrors the iOS bridge's
// `LivebuyPlugin.vodEndBehavior(fromWire:)` (identical logic; separate copy because the Swift
// source is not on this module's classpath). Zero-Android-dependency so it is JVM-unit-testable
// (VodEndBehaviorBridgeTest) per docs/unit-test-discipline.md.
object VodEndBehaviorBridge {
    fun fromWire(wire: String?): LBVodEndBehavior =
        if (wire == "advance") LBVodEndBehavior.ADVANCE else LBVodEndBehavior.LOOP
}
