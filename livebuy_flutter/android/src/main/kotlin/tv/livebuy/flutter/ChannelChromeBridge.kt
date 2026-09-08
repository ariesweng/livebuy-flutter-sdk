package tv.livebuy.flutter

// player-channel-chrome-bridge-core-flutter — pure decision + payload helpers for the Flutter
// Android bridge's `channelChange` EventChannel emit. MIRRORS the iOS bridge's private
// `ChannelChromeSnapshot` struct + emit logic (identical logic; a separate copy because the iOS
// Swift source is not on this module's classpath) — parallels this same package's
// `SubtitleChannelBridge` structure, but the dedupe key here covers the FULL 13-field projection
// (channel-type-bridge-core-flutter added the 10th, `type`; product-list-bridge-core-flutter
// added the 11th, `goods`; channel-shop-intro-bridge-core-flutter added the 12th, `shopIntro`;
// guest-comment-channel-bridge-core-flutter added the 13th, `guestComment`),
// NOT a single channel id: a channel can flip `liveStatus` (upcoming →
// live, the 30s preview poll) while keeping the same id, and that IS a real change this event
// must still carry.
//
// [Snapshot] is a plain data class (zero-Android-dependency) so `shouldEmit`/`payload` are
// trivially JVM-unit-testable (ChannelChromeBridgeTest) per docs/unit-test-discipline.md — the
// view's own wiring (read `LivebuyPlayerView.channel`, call `LivebuyEventHandler.emit`) is the
// untestable side-effect shell around this pure core. Mirrors this same package's
// `SubtitleChannelBridge` / `AutoPipPolicy`.
object ChannelChromeBridge {

    /**
     * The 15 fields projected from a loaded `LBChannel` onto the `channelChange` wire payload.
     * Compared AS A WHOLE by [shouldEmit] — not just [liveStatus] or a channel id — so that any
     * single field change (most notably an upcoming→live `liveStatus` flip on the SAME channel)
     * is not silently dropped by a narrower id-only dedupe key. Unlike the iOS bridge's mirrored
     * struct, [goods] and [otherGoods] can be dropped in here as plain `List<Map<String, Any?>>`
     * (the already wire-serialized product list, built via the existing `productToMap`) with no
     * extra fingerprint type needed — Kotlin's `List`/`Map` already have correct structural
     * `equals()`, so this `data class`'s auto-generated `equals()` compares both correctly for
     * free.
     */
    data class Snapshot(
        val publishAt: String,
        val cover: String,
        val start: String,
        val liveStatus: Int,
        val title: String,
        val serviceLink: String,
        val shopName: String,
        val shopLogo: String,
        val shareUrl: String,
        val type: Int,
        val goods: List<Map<String, Any?>>,
        val shopIntro: String,
        val guestComment: Int,
        // channel-diversion-bridge-core-flutter: raw `channel.diversion` passthrough — the
        // Flutter reference-ui container's default `onProductTap` needs this to call
        // `DefaultPlayerTemplate.handleProductTap(product:diversion:)` correctly. Without it every
        // product tap fell through the dead `simulateProductTap` native round-trip (no Dart
        // listener ever consumed the resulting `productTap` event), so the product-detail /
        // add-to-cart / restock-notify sheets never opened for a `diversion == 0` channel, and a
        // `diversion == 1` channel's purchase-page URL never opened either.
        val diversion: Int,
        // rb-flutter-other-goods-channel-bridge-core: cross-video recommended products
        // (`channel.other_goods`), a DIFFERENT list from [goods] above (which is the
        // currently loaded channel's OWN sellable products). Same already-wire-serialized
        // `List<Map<String, Any?>>` shape as [goods] (built via the existing `productToMap`),
        // for the same free-structural-equals reason.
        val otherGoods: List<Map<String, Any?>>,
    )

    /**
     * Dedupe gate: should we (re-)emit `channelChange` for [current], given the [last] snapshot we
     * emitted (`null` on the very first emit → always true)? Re-emits whenever ANY of the 13
     * projected fields differs from the last emitted snapshot.
     */
    fun shouldEmit(current: Snapshot, last: Snapshot?): Boolean = current != last

    /**
     * Builds the `channelChange` EventChannel payload (minus the `"event"` key — the call site
     * adds that, keeping this function a pure data-shape mapper). Keys match
     * `LBPlayerChannelInfo.fromMap`'s existing camelCase convention.
     */
    fun payload(snapshot: Snapshot): Map<String, Any?> = mapOf(
        "publishAt" to snapshot.publishAt,
        "cover" to snapshot.cover,
        "start" to snapshot.start,
        "liveStatus" to snapshot.liveStatus,
        "title" to snapshot.title,
        "serviceLink" to snapshot.serviceLink,
        "shopName" to snapshot.shopName,
        "shopLogo" to snapshot.shopLogo,
        "shareUrl" to snapshot.shareUrl,
        "type" to snapshot.type,
        "goods" to snapshot.goods,
        "shopIntro" to snapshot.shopIntro,
        "guestComment" to snapshot.guestComment,
        "diversion" to snapshot.diversion,
        "otherGoods" to snapshot.otherGoods,
    )
}
