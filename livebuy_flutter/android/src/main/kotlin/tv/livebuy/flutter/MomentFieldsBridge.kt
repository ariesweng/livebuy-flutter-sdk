package tv.livebuy.flutter

import tv.livebuy.sdk.models.LBHotItem
import tv.livebuy.sdk.models.LBNavItem

// player-moment-fields-bridge-core-flutter — pure decision + payload helpers for the Flutter
// Android bridge's `momentStateChange` EventChannel emit. MIRRORS the iOS bridge's private
// `MomentFieldsSnapshot` struct + emit logic (identical logic; a separate copy because the iOS
// Swift source is not on this module's classpath) — parallels this same package's
// `ChannelChromeBridge` structure. Scoped to exactly the 6 `LBPlayerMomentState` fields with a
// currently-starved Dart-side `flutter-ui` consumer (design.md D2) — the other 12 fields each
// already have an established, independent Flutter derivation path and are deliberately NOT
// bridged here.
//
// [Snapshot] is a plain data class (zero-Android-dependency) so `shouldEmit`/`payload` are
// trivially JVM-unit-testable (MomentFieldsBridgeTest) per docs/unit-test-discipline.md — the
// view's own wiring (read `LivebuyPlayerView.onMomentStateChange`, call
// `LivebuyEventHandler.emit`) is the untestable side-effect shell around this pure core.
object MomentFieldsBridge {

    /**
     * The 6 fields projected from a native `LBPlayerMomentState` publish onto the
     * `momentStateChange` wire payload. Compared AS A WHOLE by [shouldEmit] so any single field
     * change (most notably a per-second `autoNextRemainingSeconds` tick while the countdown is
     * active) is not silently dropped by a narrower dedupe key. Unlike the iOS bridge's mirrored
     * struct, [nextItem]/[hotItems] need no extra fingerprint type here — Kotlin `data class`
     * structural equality on `LBNavItem`/`LBHotItem` (themselves `data class`es) already gives
     * correct `equals()` for free (doc-commented asymmetry vs. iOS, where neither native struct
     * conforms to `Equatable`).
     */
    data class Snapshot(
        val viewerCount: Int,
        val isSubscribed: Boolean,
        val autoNextCountdownActive: Boolean,
        val autoNextRemainingSeconds: Int,
        val nextItem: LBNavItem?,
        val hotItems: List<LBHotItem>,
    )

    /**
     * Dedupe gate: should we (re-)emit `momentStateChange` for [current], given the [last]
     * snapshot we emitted (`null` on the very first emit → always true)? Re-emits whenever ANY
     * of the 6 projected fields differs from the last emitted snapshot — including a
     * viewerCount-only change or a per-second `autoNextRemainingSeconds` decrement.
     */
    fun shouldEmit(current: Snapshot, last: Snapshot?): Boolean = current != last

    /**
     * Builds the `momentStateChange` EventChannel payload (minus the `"event"` key — the call
     * site adds that, keeping this function a pure data-shape mapper). `nextItem` key is
     * entirely ABSENT (not present-with-null) when [Snapshot.nextItem] is `null` — mirrors iOS's
     * omit-when-nil convention (design D6).
     */
    fun payload(snapshot: Snapshot): Map<String, Any?> {
        val body = mutableMapOf<String, Any?>(
            "viewerCount" to snapshot.viewerCount,
            "isSubscribed" to snapshot.isSubscribed,
            "autoNextCountdownActive" to snapshot.autoNextCountdownActive,
            "autoNextRemainingSeconds" to snapshot.autoNextRemainingSeconds,
            "hotItems" to snapshot.hotItems.map { hotItemToMap(it) },
        )
        snapshot.nextItem?.let { body["nextItem"] = navItemToMap(it) }
        return body
    }
}
