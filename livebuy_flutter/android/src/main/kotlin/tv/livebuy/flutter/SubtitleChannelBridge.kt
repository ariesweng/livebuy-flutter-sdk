package tv.livebuy.flutter

// rb-flutter-subtitle-channel-bridge-core — pure decision + payload helpers for the Flutter
// Android bridge's `subtitleChange` EventChannel emit. MIRRORS the iOS bridge's
// `flutterSubtitleShouldEmit` / `flutterSubtitlePayload` free functions (identical logic; a
// separate copy because the iOS Swift source is not on this module's classpath).
//
// These functions carry the ONLY branching logic of the subtitle-channel bridge in
// [LivebuyFlutterPlayerView] (whether to (re-)emit for a given channel id, and how the payload is
// shaped). They are deliberately ZERO-Android-dependency (plain String / Int / Map) so they are
// trivially JVM-unit-testable (SubtitleChannelBridgeTest) per docs/unit-test-discipline.md — the
// view's own wiring (read `LivebuyPlayerView.channel`, call `LivebuyEventHandler.emit`) is the
// untestable side-effect shell around this pure core. Mirrors this same package's `AutoPipPolicy`.
object SubtitleChannelBridge {

    /**
     * Dedupe gate: should we (re-)emit `subtitleChange` for [channelId], given the last id we
     * emitted for ([lastEmittedId], `null` on the very first emit → always true)? Re-emits
     * exactly once per distinct loaded channel id — `onStateChange` fires on every player-state
     * transition (loading/buffering/playing/…) even though subtitle data is static per channel.
     */
    fun shouldEmit(channelId: String, lastEmittedId: String?): Boolean =
        channelId != lastEmittedId

    /**
     * Builds the `subtitleChange` EventChannel payload (minus the `"event"` key — the call site
     * adds that, keeping this function a pure data-shape mapper). [isSubtitle] is the raw native
     * Int flag (0/1) from `LBChannel.isSubtitle`; `available` on the wire is the Bool it decodes
     * to. [subtitleUrl] is `LBChannel.subtitleUrl`, passed through raw.
     */
    fun payload(isSubtitle: Int, subtitleUrl: String): Map<String, Any?> = mapOf(
        "available" to (isSubtitle == 1),
        "url" to subtitleUrl,
    )
}
