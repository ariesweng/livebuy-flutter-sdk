package tv.livebuy.flutter

import tv.livebuy.sdk.models.LBHotItem
import tv.livebuy.sdk.models.LBNavItem

// player-moment-fields-bridge-core-flutter — pure decision + payload helpers for the Flutter
// Android bridge's `momentStateChange` EventChannel emit. MIRRORS the iOS bridge's private
// `MomentFieldsSnapshot` struct + emit logic (identical logic; a separate copy because the iOS
// Swift source is not on this module's classpath) — parallels this same package's
// `ChannelChromeBridge` structure. Originally scoped to exactly 6 `LBPlayerMomentState` fields
// with a currently-starved Dart-side `flutter-ui` consumer (design.md D2) — the other 12 fields
// each already have an established, independent Flutter derivation path and are deliberately NOT
// bridged here.
//
// flutter-android-moment-products-bridge-core — that "already established" assumption did NOT
// hold for `products`/`narratingProduct`: Flutter's only product data source was `channelChange`'s
// `goods` field, a channel-LOAD-TIME-ONLY snapshot (see `forwardChannelChangeToTemplate`'s own
// doc comment in `flutter-reference-ui`), never updated as `narrate_status` changes mid-stream —
// unlike the moment-state `narratingProduct` iOS/Android/RN reference-ui actually use for the LIVE
// 介紹中商品卡. `products`/`narratingProduct` are now ALSO bridged here (iOS parity landed same-day
// via flutter-ios-moment-products-bridge-core; see each field's own doc comment), extending the
// snapshot from 6 to 8 fields.
//
// [Snapshot] is a plain data class (zero-Android-dependency) so `shouldEmit`/`payload` are
// trivially JVM-unit-testable (MomentFieldsBridgeTest) per docs/unit-test-discipline.md — the
// view's own wiring (read `LivebuyPlayerView.onMomentStateChange`, call
// `LivebuyEventHandler.emit`) is the untestable side-effect shell around this pure core.
object MomentFieldsBridge {

    /**
     * The fields projected from a native `LBPlayerMomentState` publish onto the
     * `momentStateChange` wire payload. Compared AS A WHOLE by [shouldEmit] so any single field
     * change (most notably a per-second `autoNextRemainingSeconds` tick, or a `products`-only
     * `narrate_status` flip while nothing else changed) is not silently dropped by a narrower
     * dedupe key. [nextItem]/[hotItems]/[products]/[narratingProduct] need no extra fingerprint
     * type here — Kotlin `data class`/`List`/`Map` structural equality already gives correct
     * `equals()` for free (doc-commented asymmetry vs. iOS, where neither native struct conforms
     * to `Equatable`).
     */
    data class Snapshot(
        val viewerCount: Int,
        val isSubscribed: Boolean,
        val autoNextCountdownActive: Boolean,
        val autoNextRemainingSeconds: Int,
        val nextItem: LBNavItem?,
        val hotItems: List<LBHotItem>,
        // flutter-android-moment-products-bridge-core — the currently-loaded channel's FULL
        // product list, already wire-serialized via the SAME `productToMap` helper
        // `ChannelChromeBridge`'s `goods`/`otherGoods` use (structural parity, no separate
        // serialization logic). Reflects live `narrate_status` changes every poll round
        // (`LivebuyPlayerView.pollVideoState()`, independent of the chat-message `PollManager`).
        val products: List<Map<String, Any?>>,
        // The single representative `narrate_status == 2` product (native's own `firstOrNull`
        // simplification — see `LBPlayerMomentState.narratingProduct`'s own doc comment for why
        // the FULL multi-narrating-product set is instead derived from [products] downstream, not
        // from this field). `null` when no product is currently being narrated.
        val narratingProduct: Map<String, Any?>?,
        // rb-flutter-endscreen-live-duration — mirrors native `LBPlayerMomentState
        // .liveDurationSeconds` (added by `endscreen-live-duration-android-core`): the raw second
        // count of this live's currently-known playback duration, sourced from
        // `StatContextStore.liveTime(videoId)`. `null` means no value has been obtained yet (a
        // VOD, a Player instance that has not yet received a goods-poll response, or
        // `enableStatReporting == false`) — raw second count, NOT a pre-formatted string;
        // formatting is a reference-ui concern.
        val liveDurationSeconds: Int? = null,
    )

    /**
     * Dedupe gate: should we (re-)emit `momentStateChange` for [current], given the [last]
     * snapshot we emitted (`null` on the very first emit → always true)? Re-emits whenever ANY
     * of the projected fields differs from the last emitted snapshot — including a
     * viewerCount-only change, a per-second `autoNextRemainingSeconds` decrement, or a
     * `products`-only `narrate_status` flip with every other field unchanged.
     */
    fun shouldEmit(current: Snapshot, last: Snapshot?): Boolean = current != last

    /**
     * Builds the `momentStateChange` EventChannel payload (minus the `"event"` key — the call
     * site adds that, keeping this function a pure data-shape mapper). `nextItem` / `narratingProduct`
     * keys are entirely ABSENT (not present-with-null) when the corresponding [Snapshot] field is
     * `null` — mirrors iOS's omit-when-nil convention (design D6). `products` is always present
     * (an empty list, not an absent key, when the channel has no products).
     */
    fun payload(snapshot: Snapshot): Map<String, Any?> {
        val body = mutableMapOf<String, Any?>(
            "viewerCount" to snapshot.viewerCount,
            "isSubscribed" to snapshot.isSubscribed,
            "autoNextCountdownActive" to snapshot.autoNextCountdownActive,
            "autoNextRemainingSeconds" to snapshot.autoNextRemainingSeconds,
            "hotItems" to snapshot.hotItems.map { hotItemToMap(it) },
            "products" to snapshot.products,
        )
        snapshot.nextItem?.let { body["nextItem"] = navItemToMap(it) }
        snapshot.narratingProduct?.let { body["narratingProduct"] = it }
        snapshot.liveDurationSeconds?.let { body["liveDurationSeconds"] = it }
        return body
    }
}
