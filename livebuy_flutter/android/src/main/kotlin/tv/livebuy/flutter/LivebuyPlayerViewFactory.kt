package tv.livebuy.flutter

import android.app.Activity
import android.app.Application
import android.app.PictureInPictureParams
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import tv.livebuy.sdk.events.LBCartResultCallback
import tv.livebuy.sdk.events.LBEvent
import tv.livebuy.sdk.events.LBListenerToken
import tv.livebuy.sdk.events.LBShareContext
import tv.livebuy.sdk.events.LivebuyEventListener
import tv.livebuy.sdk.models.LBAward
import tv.livebuy.sdk.models.LBAwardClaimInput
import tv.livebuy.sdk.models.LBComment
import tv.livebuy.sdk.models.LBError
import tv.livebuy.sdk.models.LBHotItem
import tv.livebuy.sdk.models.LBNavItem
import tv.livebuy.sdk.models.LBPlayerState
import tv.livebuy.sdk.models.LBPollResponse
import tv.livebuy.sdk.models.LBProduct
import tv.livebuy.sdk.models.LBSpec
import tv.livebuy.sdk.models.LBSpecOption
import tv.livebuy.sdk.models.LBWinner
import tv.livebuy.sdk.player.LBLiveVideoSurfaceMode
import tv.livebuy.sdk.player.LivebuyPlayerView
import tv.livebuy.sdk.player.PiPHelper
import tv.livebuy.sdk.player.VideoInfoPanel
import tv.livebuy.sdk.player.pollReceivedEventParams

// messenger is needed to set up per-view MethodChannels; appContext is required by LivebuyPlayerView (not the scoped Activity context).
// activityProvider (flutter-android-auto-pip-entry): supplies the host Activity so each view can
// arm OS auto-PiP + call PiPHelper.enterPiP. Resolved at view-create time so a config-change-
// recreated Activity is always current; null → the view safely skips PiP wiring (no crash).

class LivebuyPlayerViewFactory(
    private val messenger: BinaryMessenger,
    private val appContext: Context,
    private val activityProvider: () -> Activity? = { null }
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<String, Any>()
        return LivebuyFlutterPlayerView(context, viewId, messenger, params, activityProvider)
    }
}

class LivebuyFlutterPlayerView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    params: Map<*, *>,
    activityProvider: () -> Activity? = { null }
) : PlatformView {

    private val playerView = LivebuyPlayerView(context)
    private val methodChannel = MethodChannel(messenger, "tv.livebuy/player_$viewId")
    /// Per-view scope for suspend-fun bridges (sendChat). Cancelled on dispose().
    private val bridgeScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // flutter-android-auto-pip-entry — the per-view OS auto-PiP wiring (arm + PIP_STATE_CHANGE
    // consumer + opt-in onUserLeaveHint forward). Strongly retains the auxiliary event listener
    // (core `addEventListener` holds it WEAKLY). Torn down in dispose(). Null when no host Activity
    // was available at create time.
    private var autoPipWiring: AutoPipWiring? = null

    // rb-flutter-subtitle-channel-bridge-core: last channel id we emitted a `subtitleChange`
    // payload for, so a same-channel state-machine tick (loading→buffering→playing, …) does not
    // re-emit. Reset naturally on a real channel switch (see SubtitleChannelBridge.shouldEmit);
    // no explicit reset needed at dispose().
    private var lastSubtitleChannelId: String? = null

    // player-channel-chrome-bridge-core-flutter: last channel-chrome snapshot we emitted a
    // `channelChange` payload for (ALL 9 projected fields, not just channel id — an upcoming→live
    // `liveStatus` flip keeps the same id but IS a real change this event must still carry).
    // Independent of `lastSubtitleChannelId` above — the two piggybacks do not share dedupe state.
    private var lastChannelChromeSnapshot: ChannelChromeBridge.Snapshot? = null

    // player-moment-fields-bridge-core-flutter: last moment-fields snapshot we emitted a
    // `momentStateChange` payload for (ALL 6 projected fields). Independent of
    // `lastChannelChromeSnapshot`/`lastSubtitleChannelId` above — none of these three dedupe
    // mechanisms gate or suppress either of the others (design.md D4).
    private var lastMomentFieldsSnapshot: MomentFieldsBridge.Snapshot? = null

    init {
        // flutter-android-texture-layer-composition-core: make the live (IVS) engine render into a
        // `TextureView` instead of its default `SurfaceView`. MUST be set right after constructing
        // `playerView` and BEFORE any `load()` — core contract (`LBLiveVideoSurfaceMode` doc: the
        // value is read when the IVS engine is lazily created on the first live load), hence the
        // very first statement of this init block, ahead of the method-channel `load` handler (the
        // sole `load()` trigger on Android — see the
        // fix-flutter-android-duplicate-load-on-platform-view-create comment further down this
        // init block). With VOD / replay / intro already on `TextureView`
        // (`lb_exo_player_view.xml`), the native view tree this platform view wraps never contains
        // a `SurfaceView`, so the Dart side's Texture Layer mount (`initSurfaceAndroidView`,
        // `livebuy_player.dart`) never falls back to Hybrid Composition and no `SurfaceView` can
        // punch through the Flutter overlays. Bridge-internal decision — deliberately NOT a
        // `creationParams` / method-channel field (spec `flutter-android-player-view-composition`).
        playerView.liveVideoSurfaceMode = LBLiveVideoSurfaceMode.TEXTURE_VIEW

        playerView.onStateChange = { state ->
            val raw = when (state) {
                LBPlayerState.LOADING -> "loading"
                LBPlayerState.BUFFERING -> "buffering"
                LBPlayerState.PLAYING -> "playing"
                LBPlayerState.PAUSED -> "paused"
                LBPlayerState.ENDED -> "ended"
                LBPlayerState.ERROR -> "error"
                // MARK: - decouple-ui-from-logic sub-states
                LBPlayerState.AWAITING_LIVE -> "awaitingLive"
                LBPlayerState.START_SCREEN_PLAYING -> "startScreenPlaying"
                LBPlayerState.END_SCREEN_SHOWN -> "endScreenShown"
            }
            LivebuyEventHandler.emit(mapOf("event" to "stateChange", "state" to raw))

            // rb-flutter-subtitle-channel-bridge-core: piggyback on this ALREADY-EXISTING hook to
            // read the ALREADY-PUBLIC `channel` property (no new native hook added, no
            // android/livebuy/ change). `channel` is set synchronously before configureFromChannel
            // runs, so it is fresh by the time any state after the very first cold-start LOADING
            // tick fires; a still-null channel is simply skipped (self-corrects on the next tick).
            playerView.channel?.let { ch ->
                if (SubtitleChannelBridge.shouldEmit(ch.id, lastSubtitleChannelId)) {
                    lastSubtitleChannelId = ch.id
                    LivebuyEventHandler.emit(
                        SubtitleChannelBridge.payload(ch.isSubtitle, ch.subtitleUrl) +
                            ("event" to "subtitleChange")
                    )
                }
            }

            // player-channel-chrome-bridge-core-flutter: piggyback on this ALREADY-EXISTING
            // hook to read the ALREADY-PUBLIC `channel` property (no new native hook added, no
            // android/livebuy/ change), independent of the subtitle piggyback above (own dedupe
            // state — see `lastChannelChromeSnapshot` / `ChannelChromeBridge`). Unlike the iOS
            // bridge's subtitle block, this Kotlin `?.let { }` scope function never returns from
            // the enclosing `onStateChange` lambda, so placement relative to the subtitle block
            // above does not matter here.
            playerView.channel?.let { ch ->
                val snapshot = ChannelChromeBridge.Snapshot(
                    publishAt = ch.publishAt,
                    cover = ch.cover,
                    start = ch.start,
                    liveStatus = ch.liveStatus,
                    title = ch.title,
                    serviceLink = ch.shop.serviceLink,
                    shopName = ch.shop.name,
                    shopLogo = ch.shop.logo,
                    shareUrl = ch.shareUrl,
                    type = ch.type,
                    // product-list-bridge-core-flutter: reuses the existing
                    // `productToMap` helper `onProductTap` already serializes
                    // `LBProduct` with — no new wire shape.
                    goods = ch.goods.map { productToMap(it) },
                    // channel-shop-intro-bridge-core-flutter: shop introduction text.
                    // May legitimately be "" (merchant left it blank).
                    shopIntro = ch.shop.intro,
                    // guest-comment-channel-bridge-core-flutter: raw permission flag
                    // passthrough — does NOT compute `chatEnabled` here.
                    guestComment = ch.guestComment,
                    // channel-diversion-bridge-core-flutter: raw passthrough, see
                    // `ChannelChromeBridge.Snapshot.diversion`'s own doc comment.
                    diversion = ch.diversion,
                    // rb-flutter-other-goods-channel-bridge-core: cross-video
                    // recommended products — reuses the SAME `productToMap` helper
                    // `goods` above uses, no extra API call needed.
                    otherGoods = ch.otherGoods.map { productToMap(it) },
                    // channel-flash-sale-flag-core-flutter: raw top-level
                    // `channel.isFlashSale` passthrough (NOT `ch.shop.isFlashSale`).
                    isFlashSale = ch.isFlashSale,
                    // channel-notice-bridge-core-flutter: raw top-level
                    // `channel.notice` / `channel.sysNotice` passthrough (NOT
                    // `ch.shop.notice` / `ch.shop.sysNotice`).
                    notice = ch.notice,
                    sysNotice = ch.sysNotice,
                )
                if (ChannelChromeBridge.shouldEmit(snapshot, lastChannelChromeSnapshot)) {
                    lastChannelChromeSnapshot = snapshot
                    LivebuyEventHandler.emit(
                        ChannelChromeBridge.payload(snapshot) + ("event" to "channelChange")
                    )
                }
            }
        }

        playerView.onProductTap = { product ->
            // product-bridge-data-core: emit the full field set (camelCase
            // keys per design D1) incl. nested specifications / specOptions.
            val payload = productToMap(product).toMutableMap()
            payload["event"] = "productTap"
            LivebuyEventHandler.emit(payload)
        }

        playerView.onPollReceived = { resp ->
            // core-flutter-poll-params：序列化完整統一 POLL_RECEIVED params（last/push（帶 kind/reply/
            // reply_color）/user/rush/win/live_end?/top?）供 flutter-ui template 路由合流 feed 與
            // chat-message-taxonomy（narrate→browse、主播/回覆/AI 角色、置頂）。保留 `liveEnd`(camel)
            // 供 flutter/lib deprecated host callback `LBPollResponse.fromMap` 相容。
            val payload = mutableMapOf<String, Any?>("event" to "pollReceived")
            payload.putAll(pollReceivedEventParams(resp))
            resp.liveEnd?.let { payload["liveEnd"] = it }
            LivebuyEventHandler.emit(payload)
        }

        playerView.onError = { error ->
            val payload = mutableMapOf<String, Any?>("event" to "error")
            when (error) {
                is LBError.Restricted       -> payload["type"] = "restricted"
                is LBError.VideoNotFound    -> payload["type"] = "videoNotFound"
                is LBError.InvalidSignature -> payload["type"] = "invalidSignature"
                is LBError.ChatRateLimited  -> payload["type"] = "chatRateLimited"
                // commentsub-checkname-contract-core §8.2: chat business errors.
                is LBError.GuestNameTaken   -> payload["type"] = "guestNameTaken"
                is LBError.ChatRequiresLogin -> payload["type"] = "chatRequiresLogin"
                is LBError.NotLive          -> payload["type"] = "notLive"
                is LBError.SdkVersionUnsupported -> payload["type"] = "sdk_version_unsupported"
                is LBError.NetworkError -> {
                    payload["type"] = "networkError"
                    payload["message"] = error.cause.localizedMessage ?: "Network error"
                }
                is LBError.ServerError -> {
                    payload["type"] = "serverError"
                    payload["code"] = error.code
                    payload["message"] = error.message
                }
                is LBError.LoginFailed -> {
                    // login() surfaces failures via the method-channel error path;
                    // event mapping is a fallback. No dedicated Dart union member —
                    // map to serverError.
                    payload["type"] = "serverError"
                    payload["code"] = error.code
                    payload["message"] = error.message
                }
                is LBError.SdkConfigFetchFailed -> {
                    payload["type"] = "networkError"
                    payload["message"] = error.underlying?.localizedMessage ?: "config fetch failed"
                }
                else -> {
                    // NotConfigured / future cases — avoid a silent empty event.
                    payload["type"] = "serverError"
                    payload["code"] = -1
                    payload["message"] = "unknown error"
                }
            }
            LivebuyEventHandler.emit(payload)
        }

        // flutter-vod-playback-progress-core — VOD-1 playback-progress forward.
        // `LivebuyPlayerView.onPlaybackProgressChange` already exists natively
        // (Android isReplay-slice parity), so this is a real hook (unrelated to the
        // onStateChange-piggybacked channelChange/subtitleChange emits above, which read
        // `channel` from the existing state-change hook instead of needing a dedicated one).
        // vod-narrating-products-core-flutter: additive `products` wire key — the
        // raw, unfiltered `channel.goods` snapshot (same source core's own
        // `vodActiveProducts(products:position:)` reads), serialized via the same
        // `productToMap(_:)` helper `onProductTap` uses. Dart independently
        // filters by `[beginTime, endTime)` + `position` (component-contracts
        // `Player（Flutter）VOD playback-progress 頻道與控制出口 — core bridge
        // parity`). No weak-capture ceremony needed — this file's other closures
        // already reference the outer `playerView` property directly.
        playerView.onPlaybackProgressChange = { progress ->
            LivebuyEventHandler.emit(
                mapOf(
                    "event" to "playbackProgress",
                    "position" to progress.position,
                    "duration" to progress.duration,
                    "isPlaying" to progress.isPlaying,
                    "isReplay" to progress.isReplay,
                    "products" to (playerView.channel?.goods ?: emptyList()).map { productToMap(it) },
                )
            )
        }

        // player-moment-fields-bridge-core-flutter — a genuinely NEW, dedicated native hook
        // assignment (design D1), not a piggyback: `onMomentStateChange` is itself the
        // purpose-built hook, already firing on every real moment-state publish on Android.
        // Scoped to exactly the 6 fields with a currently-starved Dart-side `flutter-ui`
        // consumer (design D2) — the other 12 `LBPlayerMomentState` fields each already have an
        // established, independent Flutter derivation path and are deliberately NOT bridged
        // here. Whole-snapshot dedupe (design D4) so the high-frequency native publish (fires on
        // subtitle toggles, chat-visibility flips, product-overlay refreshes — none of which are
        // in our 6 fields) does not spam the EventChannel; a per-second countdown tick DOES
        // re-emit because `autoNextRemainingSeconds` is itself part of the snapshot.
        playerView.onMomentStateChange = { state ->
            // flutter-android-moment-products-bridge-core: `products`/`narratingProduct`
            // reuse the SAME `productToMap` helper the `channelChange` `goods` field above
            // uses (structural parity). This is what powers the LIVE 介紹中商品卡 /
            // dynamically-updating product list on the Flutter side — see this file's
            // `MomentFieldsBridge.kt` sibling for the full rationale.
            val snapshot = MomentFieldsBridge.Snapshot(
                viewerCount = state.viewerCount,
                isSubscribed = state.isSubscribed,
                autoNextCountdownActive = state.autoNextCountdownActive,
                autoNextRemainingSeconds = state.autoNextRemainingSeconds,
                nextItem = state.nextItem,
                hotItems = state.hotItems,
                products = state.products.map { productToMap(it) },
                narratingProduct = state.narratingProduct?.let { productToMap(it) },
            )
            if (MomentFieldsBridge.shouldEmit(snapshot, lastMomentFieldsSnapshot)) {
                lastMomentFieldsSnapshot = snapshot
                LivebuyEventHandler.emit(
                    MomentFieldsBridge.payload(snapshot) + ("event" to "momentStateChange")
                )
            }
        }

        // replay-chat-revealed-seam-core-flutter — direct closure subscription to the
        // already-existing native seam `LivebuyPlayerView.onReplayChatRevealed` (no new
        // native SDK hook, no android/livebuy/ change). Mirrors `onPlaybackProgressChange`
        // above (NOT the `onStateChange` piggyback pattern used for
        // channelChange/subtitleChange) because this seam's fire timing (progressive
        // reveal / seek shrink / reset-to-[]) is driven by the native replay-timeline
        // scheduler on its own event-driven schedule, independent of player-state ticks.
        // Every native emit (including `[]` cleanup emits) is forwarded 1:1 — no
        // re-derived timing logic, no new dedupe state on this side (design D1/D6).
        playerView.onReplayChatRevealed = { comments ->
            LivebuyEventHandler.emit(
                mapOf(
                    "event" to "replayChatRevealed",
                    "comments" to comments.map { commentToMap(it) },
                )
            )
        }

        methodChannel.setMethodCallHandler { call, result ->
            val callArgs = call.arguments as? Map<*, *>
            when (call.method) {
                "load"     -> { playerView.load(callArgs?.get("videoId") as String); result.success(null) }
                // `release` is the legacy method name (pre-headless API).
                // headless SDK renamed it to `unload`; alias preserved.
                "release"  -> { playerView.unload(); result.success(null) }
                "unload"   -> { playerView.unload(); result.success(null) }
                "play"     -> { playerView.play(); result.success(null) }
                "pause"    -> { playerView.pause(); result.success(null) }
                "setMuted" -> { playerView.setMuted(callArgs?.get("muted") as Boolean); result.success(null) }
                // mute-preference-persist-across-session-flutter-core — read-only query
                // exit forwarding the already-public core getter `playerView.isMuted`
                // (mirrors iOS `LivebuyPlayerViewController.isMuted`). Pure passthrough,
                // no new state on this side.
                "isMuted"  -> { result.success(playerView.isMuted) }
                "seek"     -> { playerView.seek((callArgs?.get("seconds") as Number).toDouble()); result.success(null) }
                // flutter-vod-scrub-seek-tolerance-core — drag-to-scrub precision hints, no
                // position change of their own; see LivebuyPlayerView.beginScrub()/endScrub().
                //
                // NOTE (history): a 2026-09-17 experiment detached the video surface across the
                // whole drag (mirroring the since-removed PiP detach hack) to cut Hybrid
                // Composition's per-frame recomposite cost during a slow scrub — it blanked the
                // video for the ENTIRE drag and was reverted. flutter-android-texture-layer-
                // composition-core removed that underlying cost itself: the player no longer
                // mounts via Hybrid Composition (Texture Layer composition, see
                // `livebuy_player.dart` and `installAutoPip` (5) below), so scrub-drag jank is
                // mitigated only by the existing Android-only 30fps visual throttle in
                // `playback_progress_bar_view.dart`
                // (`flutter-android-scrub-drag-visual-throttle-reference-ui`) on top of the
                // cheaper composition — no video-surface detach anywhere in this bridge.
                "beginScrub" -> { playerView.beginScrub(); result.success(null) }
                "endScrub"   -> { playerView.endScrub(); result.success(null) }
                // flutter-vod-playback-progress-core — VOD-1 control exits.
                // fix-flutter-android-toggle-play-pause-bridge: togglePlayPause now forwards
                // directly to the real native LivebuyPlayerView.togglePlayPause() (added by
                // android-vod-playback-progress-core-parity). The prior play()/pause()
                // composition never flipped canonical playerState — Android engines don't
                // re-fire onStateChange on a bare pause/resume — so the progress pump and
                // playbackProgress.isPlaying stayed stuck at the pre-pause value, and the
                // reference-ui play/pause icon never toggled (a second tap would even re-call
                // pause() instead of play()). seekBy() is left unchanged (composed bridge-side
                // from play()/pause()/seek()/playbackProgress) — narrower risk profile, out of
                // scope for this fix (see design.md).
                "togglePlayPause" -> {
                    playerView.togglePlayPause()
                    result.success(null)
                }
                "seekBy" -> {
                    val delta = (callArgs?.get("seconds") as Number).toDouble()
                    val progress = playerView.playbackProgress
                    val target = (progress.position + delta).coerceIn(0.0, maxOf(progress.duration, 0.0))
                    playerView.seek(target)
                    result.success(null)
                }
                "sendChat" -> {
                    val message = callArgs?.get("message") as String
                    val eventId = (callArgs["eventId"] as? Number)?.toInt()
                    bridgeScope.launch {
                        playerView.sendChat(message, eventId)
                    }
                    result.success(null)
                }
                // MARK: - new methods per spec §Player Public methods
                "skipStart"        -> { playerView.skipStart(); result.success(null) }
                "cancelAutoNext"   -> { playerView.cancelAutoNext(); result.success(null) }
                "requestEventJoin" -> {
                    playerView.requestEventJoin(
                        (callArgs?.get("eid") as Number).toInt(),
                        callArgs["keyword"] as String,
                    )
                    result.success(null)
                }
                "requestViewCart" -> {
                    // view-cart-event-flutter-core: 查看購物車 CTA → core seam (emit VIEW_CART).
                    // productId null（列表底部 CTA）→ native 省略 product_id key。
                    playerView.requestViewCart(callArgs?.get("productId") as? String)
                    result.success(null)
                }
                "reportEventStay" -> {
                    // 直播抽獎停留補登（fire-and-forget；native reportEventStay 自行背景送出）。
                    playerView.reportEventStay(
                        (callArgs?.get("eventId") as Number).toInt(),
                        (callArgs["stayTime"] as? Number)?.toInt(),
                    )
                    result.success(null)
                }
                "activeEvents" -> {
                    // active-event-accessor-flutter-core: 直播抽獎「進行中活動」唯讀快照 accessor.
                    // 每筆用 public @JvmStatic LivebuyPlayerView.activeEventParams(it) 序列化（Android
                    // 可直接重用該 companion 方法；已排除 stayTime、keyword 空省略 key）→ List<Map> →
                    // result.success。無進行中活動 → 空 List。鏡像 iOS plugin activeEventBody 與 RN Android
                    // bridge（同重用 activeEventParams）。
                    result.success(
                        playerView.activeEvents().map { LivebuyPlayerView.activeEventParams(it) }
                    )
                }
                "requestAwardClaim" -> {
                    val winner = lbWinnerFrom(callArgs?.get("winner") as? Map<*, *>)
                    if (winner != null) {
                        val email = (callArgs?.get("contact") as? Map<*, *>)?.get("email") as? String
                        val contact = email?.let { LBAwardClaimInput(it) }
                        playerView.requestAwardClaim(winner, contact)
                    }
                    result.success(null)
                }
                "setGuestNicknameVerified" -> {
                    // guest-nickname-checkname-on-set-flutter: player-scoped 已驗證暱稱設定. checkName
                    // 成功才 commit（持久化 + 廣播）；結果分類經 result.error code 表達，Dart 端表現為
                    // PlatformException. bridgeScope 本身即 Dispatchers.Main，result.success/error 可
                    // 直接在 launch block 內呼叫，不需要額外的 mainHandler.post。
                    //
                    // guest-nickname-verified-fails-loudly-flutter: core 不再對「沒提交暱稱」的路徑
                    // 靜默 return（guest-nickname-verified-fails-loudly-android），所以這裡要把
                    // PRE-FLIGHT 失敗與 checkName ROUND-TRIP 失敗分開表達 —— 它們是三個不同的類別，
                    // 壓成一個 code 會讓 host 對「重試」做出錯誤判斷：
                    //   • NICKNAME_SET_PRECONDITION_FAILED — 請求根本沒送出（名稱 trim 後為空 /
                    //     尚未 load 任何影片）。重試同樣會失敗；host 要改的是呼叫的參數或時機。
                    //   • NOT_CONFIGURED — SDK 尚未 configure(...) 成功返回。初始化缺漏，同樣沒送出
                    //     任何請求。
                    //   • CHECKNAME_FAILED — 請求送出了、結果未定（網路 / server error）。這一類才
                    //     是可重試的。
                    //
                    // ⚠️ 邊界（lead design.md 決策 E 命名警語）：NicknameSetPreconditionFailed 與
                    // NotConfigured 是**同一個 sealed class LBError 的兄弟**，而「SDK 未 configure」
                    // 字面上**也是**一個未滿足的前置條件 —— 但它刻意**不**映射到
                    // NicknameSetPreconditionFailed。後者專指「名稱空白」與「尚未載入影片」兩者；
                    // 「未 configure」一律走 LBError.NotConfigured。（iOS 靠型別分割天然圈住這個
                    // 模糊 —— 那端的 notConfigured 屬獨立的 LBSDKError；Android 沒有這道邊界，故在
                    // 此逐字寫明。兩端型別歸屬不同是既有結構差異，wire code 必須一致。）
                    //
                    // 兩個新 catch MUST 排在泛 catch (t: Throwable) 之前 —— Kotlin 先寫先匹配，放在
                    // 後面會被 CHECKNAME_FAILED 整個吞掉（且編譯器不會提醒）。
                    val name = callArgs?.get("name") as? String
                        ?: run { result.error("BAD_ARG", "name required", null); return@setMethodCallHandler }
                    bridgeScope.launch {
                        try {
                            playerView.setGuestNicknameVerified(name)
                            result.success(null)
                        } catch (e: LBError.NicknameSetPreconditionFailed) {
                            result.error(
                                "NICKNAME_SET_PRECONDITION_FAILED",
                                "nickname set precondition failed (blank name, or no video loaded) — checkName was never sent",
                                null
                            )
                        } catch (e: LBError.NotConfigured) {
                            result.error(
                                "NOT_CONFIGURED",
                                "LivebuySDK.configure(...) has not returned successfully yet",
                                null
                            )
                        } catch (e: LBError.GuestNameTaken) {
                            result.error("GUEST_NAME_TAKEN", "nickname already taken", null)
                        } catch (t: Throwable) {
                            result.error("CHECKNAME_FAILED", t.message ?: "checkName failed", null)
                        }
                    }
                }
                "minimize"         -> { playerView.minimize(); result.success(null) }
                "expand"           -> { playerView.expand(); result.success(null) }
                "notifyPictureInPictureModeChanged" -> {
                    // flutter-android-pip-mode-forward-core: forward the host Activity's PiP
                    // confirmation into the wrapped native LivebuyPlayerView. Flutter host embeds
                    // this platform view in its own FlutterActivity (View-mode); Android delivers
                    // onPictureInPictureModeChanged only to the owning Activity, so the platform
                    // view cannot observe it. Calls the core public seam (android-view-mode-pip-forward-core)
                    // → setPiPActive gating (person_time / person_duration) + reassertPiPControlsLock on enter.
                    playerView.notifyPictureInPictureModeChanged(
                        callArgs?.get("isInPictureInPictureMode") as? Boolean ?: false
                    )
                    result.success(null)
                }

                // MARK: - simulate* sub-component commands (expand-simulate-bridge-parity)

                // ChatView
                "chatView_simulateSendTap" -> {
                    val text = callArgs?.get("text") as? String ?: ""
                    val eventId = (callArgs?.get("eventId") as? Number)?.toInt()
                    playerView.chatView.simulateSendTap(text, eventId)
                    result.success(null)
                }
                "chatView_simulateLoadHistoryTap" -> {
                    playerView.chatView.simulateLoadHistoryTap()
                    result.success(null)
                }
                "chatView_simulateEventJoinTap" -> {
                    val eid = (callArgs?.get("eid") as? Number)?.toInt() ?: 0
                    val keyword = callArgs?.get("keyword") as? String ?: ""
                    playerView.chatView.simulateEventJoinTap(eid, keyword)
                    result.success(null)
                }

                // ProductOverlayView
                "productOverlay_simulateProductTap" -> {
                    @Suppress("UNCHECKED_CAST")
                    lbProductFrom(callArgs as? Map<*, *>)?.let {
                        playerView.productOverlayView.simulateProductTap(it)
                    }
                    result.success(null)
                }
                "productOverlay_simulatePushCardDismiss" -> {
                    playerView.productOverlayView.simulatePushCardDismiss()
                    result.success(null)
                }
                "productOverlay_simulatePanelToggle" -> {
                    playerView.productOverlayView.simulatePanelToggle()
                    result.success(null)
                }

                // ProductListPanel
                "productListPanel_simulateProductTap" -> {
                    @Suppress("UNCHECKED_CAST")
                    lbProductFrom(callArgs as? Map<*, *>)?.let {
                        playerView.productListPanel.simulateProductTap(it)
                    }
                    result.success(null)
                }
                "productListPanel_simulateAddCart" -> {
                    @Suppress("UNCHECKED_CAST")
                    val productMap = callArgs?.get("product") as? Map<*, *>
                    @Suppress("UNCHECKED_CAST")
                    val specMap = callArgs?.get("spec") as? Map<*, *>
                    val product = lbProductFrom(productMap) ?: run { result.success(null); return@setMethodCallHandler }
                    val spec = specMap?.let { lbSpecFrom(it) }
                    playerView.productListPanel.simulateAddCart(product, spec)
                    result.success(null)
                }
                "productListPanel_simulateRestockNotice" -> {
                    @Suppress("UNCHECKED_CAST")
                    lbProductFrom(callArgs as? Map<*, *>)?.let {
                        playerView.productListPanel.simulateRestockNotice(it)
                    }
                    result.success(null)
                }

                // OperationPanelView
                "operationPanel_simulateGoodsTap" -> { playerView.operationPanelView.simulateGoodsTap(); result.success(null) }
                "operationPanel_simulateChatToggleTap" -> { playerView.operationPanelView.simulateChatToggleTap(); result.success(null) }
                "operationPanel_simulateLikeTap" -> { playerView.operationPanelView.simulateLikeTap(); result.success(null) }
                "operationPanel_simulateShareTap" -> { result.success(playerView.operationPanelView.simulateShareTap()) }
                "operationPanel_simulateSubtitleToggleTap" -> { playerView.operationPanelView.simulateSubtitleToggleTap(); result.success(null) }
                "operationPanel_simulateServiceLinkTap" -> { result.success(playerView.operationPanelView.simulateServiceLinkTap()) }
                "operationPanel_simulateMoreTap" -> { playerView.operationPanelView.simulateMoreTap(); result.success(null) }
                "operationPanel_simulateGuestNameEditTap" -> { playerView.operationPanelView.simulateGuestNameEditTap(); result.success(null) }
                "operationPanel_simulateSkipStartTap" -> { playerView.operationPanelView.simulateSkipStartTap(); result.success(null) }
                "operationPanel_simulateBackToLiveTap" -> { playerView.operationPanelView.simulateBackToLiveTap(); result.success(null) }

                // VideoInfoPanel
                "videoInfoPanel_simulateSubscribeTap" -> { playerView.videoInfoPanel.simulateSubscribeTap(); result.success(null) }
                "videoInfoPanel_simulateServiceLinkTap" -> { result.success(playerView.videoInfoPanel.simulateServiceLinkTap()) }
                "videoInfoPanel_simulateShopTap" -> { playerView.videoInfoPanel.simulateShopTap(); result.success(null) }
                "videoInfoPanel_simulateDismiss" -> { playerView.videoInfoPanel.simulateDismiss(); result.success(null) }
                "videoInfoPanel_simulateTabChange" -> {
                    val tabStr = callArgs?.get("tab") as? String ?: "info"
                    val tab = if (tabStr == "notice") VideoInfoPanel.Tab.NOTICE else VideoInfoPanel.Tab.INFO
                    playerView.videoInfoPanel.simulateTabChange(tab)
                    result.success(null)
                }

                // EndScreenView
                "endScreen_simulateCancelTap" -> { playerView.endScreenView.simulateCancelTap(); result.success(null) }
                "endScreen_simulateHotItemTap" -> {
                    @Suppress("UNCHECKED_CAST")
                    lbHotItemFrom(callArgs as? Map<*, *>)?.let {
                        playerView.endScreenView.simulateHotItemTap(it)
                    }
                    result.success(null)
                }

                else               -> result.notImplemented()
            }
        }

        // fix-flutter-android-duplicate-load-on-platform-view-create: this constructor
        // deliberately does NOT call `playerView.load(...)` from `creationParams["videoId"]`.
        // The sole `load()` trigger on Android is the `"load"` method-channel case above,
        // invoked by Dart's `_LivebuyPlayerCoreState._onPlatformViewCreated(int id)` right after
        // platform view creation is confirmed — the same path `didUpdateWidget` already reuses for
        // an in-place `videoId` change. Calling `load()` here too used to fire TWO real
        // `POST /sdk/video` requests per platform-view creation (one always discarded by the
        // native `loadGeneration` guard) and mislabeled the winning call's `isSwitchLoad` as
        // `true` on a genuine first open (see design.md of the fix change for the full call-chain
        // evidence). Mirrors `react-native/android`'s `LivebuyPlayerViewManager.createViewInstance`,
        // which likewise never calls `load()` itself. `creationParams["videoId"]` is intentionally
        // unused here now — it still flows into Dart's own `load` method-channel call.

        // flutter-android-auto-pip-entry — build the OS auto-PiP entry INTO the bridge so Flutter
        // partners don't have to write native Kotlin. The wrapped native LivebuyPlayerView is
        // HEADLESS View-mode: its requestAutoPiP() only dispatches PIP_STATE_CHANGE (it never
        // self-calls enterPictureInPictureMode() — that stays host territory per the headless
        // contract). Without this, Flutter Android could never enter PiP: nothing armed the
        // trigger, and nothing consumed the event to call enterPiP. Mirrors the RN bridge
        // (rn-android-auto-pip-entry `installAutoPip`) and the native drop-in `:livebuy-reference-ui`
        // `ArmAutoPiP` + sample `ExampleEventListener` (same core seams). activityProvider() is
        // null-guarded: no Activity → skip arming, degrade to the existing「can't enter PiP」with
        // no regression / no crash.
        activityProvider()?.let { activity ->
            autoPipWiring = installAutoPip(playerView, activity)
        }
    }

    /**
     * Wires OS auto-PiP for [view] against its host [activity] (flutter-android-auto-pip-entry):
     *  1. API 31+ → `setAutoEnterEnabled(true)` (system-driven, fully reliable, zero host code).
     *  2. API 26–30 → best-effort `onActivityStopped` → `requestAutoPiP()` (documented limitation).
     *  3. consume `PIP_STATE_CHANGE(requested=true)` → main-thread `PiPHelper.enterPiP(activity)`.
     *  4. register an opt-in `onUserLeaveHint` forward (host 升級 API 26–30 為可靠).
     *  5. register an opt-in `LivebuyPiPModeChangeHint` forward → synchronous
     *     `notifyPictureInPictureModeChanged` (watch-time gating / IVS controls lock); nothing else.
     * All decisions route through the pure [AutoPipPolicy]; the returned [AutoPipWiring] retains
     * every registration for [dispose] cleanup.
     */
    private fun installAutoPip(view: LivebuyPlayerView, activity: Activity): AutoPipWiring {
        val mainHandler = Handler(Looper.getMainLooper())

        // (1) API 31+: hand PiP entry timing entirely to the system. Guarded by an explicit
        // SDK_INT check so the API 31 `setAutoEnterEnabled` call is lint/compile-legal;
        // AutoPipPolicy carries the same threshold as the invariant.
        // android-bridge-auto-pip-disarm-on-dispose-core: remember whether the arm write actually
        // landed so dispose() can undo exactly that (and nothing the host set itself).
        val armedAutoEnter = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            AutoPipPolicy.shouldArmAutoEnter(Build.VERSION.SDK_INT, PiPHelper.isPiPSupported(activity)) &&
            setAutoEnterPiP(activity, enabled = true)

        // (2) API 26–30 best-effort: forward a GENUINE background (onActivityStopped, filtered to
        // this host Activity) to core's requestAutoPiP(). onActivityStopped (not onPause) is chosen
        // because onPause fires on ANY focus loss (e.g. a dialog) — too wide, would wrongly enter
        // PiP. Framework ActivityLifecycleCallbacks avoids any androidx.lifecycle dependency.
        val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityStopped(a: Activity) {
                if (a === activity) view.requestAutoPiP()
            }
            override fun onActivityCreated(a: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(a: Activity) {}
            override fun onActivityResumed(a: Activity) {}
            override fun onActivityPaused(a: Activity) {}
            override fun onActivitySaveInstanceState(a: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(a: Activity) {}
        }
        activity.application.registerActivityLifecycleCallbacks(lifecycleCallbacks)

        // (3) Consume PIP_STATE_CHANGE(requested=true) → actually enter PiP. Uses the core
        // multi-listener seam addEventListener (auxiliary — COEXISTS with the plugin's primary
        // Dart-forwarding listener, so Dart still receives onSdkEvent(PIP_STATE_CHANGE)); returns
        // false so it never intercepts. enterPictureInPictureMode MUST run on the main thread.
        val listener = object : LivebuyEventListener {
            override fun onEventTriggered(
                eventName: String,
                params: Map<String, Any>,
                cartCallback: LBCartResultCallback?,
                shareContext: LBShareContext?,
            ): Boolean {
                if (eventName == LBEvent.PIP_STATE_CHANGE && AutoPipPolicy.isPipRequested(params)) {
                    mainHandler.post {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            AutoPipPolicy.shouldEnterPiP(
                                Build.VERSION.SDK_INT,
                                PiPHelper.isPiPSupported(activity),
                                requested = true,
                            )
                        ) {
                            PiPHelper.enterPiP(activity)
                        }
                    }
                }
                return false
            }
        }
        val token = view.addEventListener(listener)

        // (4) opt-in onUserLeaveHint forward (host 升級 API 26–30 為可靠, see LivebuyPiPUserLeaveHint).
        val userLeaveForward: () -> Unit = { view.requestAutoPiP() }
        LivebuyPiPUserLeaveHint.register(userLeaveForward)

        // (5) forward the native PiP mode change straight into the EXISTING core seam
        // `notifyPictureInPictureModeChanged` (android-view-mode-pip-forward-core) — the same
        // seam the Dart-facing `LivebuyPlayerController.notifyPictureInPictureModeChanged`
        // (flutter-android-pip-mode-forward-core) already reaches via the method channel below,
        // just synchronous and host-wiring-optional. Activates watch-time-pause-during-PiP /
        // IVS-controls-lock for any host that adopts this wiring.
        //
        // flutter-android-texture-layer-composition-core: this forward is ONLY that seam call.
        // The former detach/reattach of the video surface around the PiP transition
        // (flutter-android-pip-video-surface-detach-core, 2026-09-17) is gone: it existed to
        // dodge the MediaCodec churn Hybrid Composition caused by tearing down / re-creating the
        // embedded view's `TextureView` for every intermediate PiP window size. The player now
        // mounts via Texture Layer composition (`initSurfaceAndroidView`, `livebuy_player.dart`)
        // with a `SurfaceView`-free native view tree (`liveVideoSurfaceMode = TEXTURE_VIEW`, set
        // in `init`), so a PiP transition is a plain window resize: the `TextureView` only
        // receives size changes and the `Player`'s render-surface binding stays intact for the
        // whole transition — exactly like the RN / native View-mode hosts that share this seam.
        // Detaching here would only blank the PiP thumbnail. Spec:
        // `flutter-android-player-view-composition` + `sdk-stat-reporting`
        // (「Flutter Android 原生快速路徑」).
        val modeChangeForward: (Boolean) -> Unit = { isInPip ->
            view.notifyPictureInPictureModeChanged(isInPip)
        }
        LivebuyPiPModeChangeHint.register(modeChangeForward)

        return AutoPipWiring(
            view, activity, token, listener, lifecycleCallbacks, userLeaveForward, modeChangeForward,
            armedAutoEnter,
        )
    }

    /**
     * Writes [enabled] into the host Activity's auto-enter-PiP params; returns whether the write
     * landed. `runCatching` because `setPictureInPictureParams` on an Activity whose manifest omits
     * `android:supportsPictureInPicture` is understood to throw (AOSP
     * `ensureValidPictureInPictureActivityParams`; same posture as native reference-ui's
     * `setAutoEnterPiP`): a caught failure is reported as "did not arm", never as success.
     * Only `autoEnterEnabled` is written — PiP params merge per field, so the aspect ratio set at
     * arm time is left alone on disarm.
     */
    private fun setAutoEnterPiP(activity: Activity, enabled: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return runCatching {
            val builder = PictureInPictureParams.Builder().setAutoEnterEnabled(enabled)
            if (enabled) builder.setAspectRatio(Rational(9, 16))
            activity.setPictureInPictureParams(builder.build())
        }.isSuccess
    }

    override fun getView() = playerView
    // unload() stops ExoPlayer, PollManager, VideoStatePollManager, sold-out
    // scanner and cancels the orchestrator's coroutine scope. Must be called
    // before Android GC reclaims the view to avoid timer leaks.
    override fun dispose() {
        // flutter-android-auto-pip-entry — release the per-view auto-PiP wiring so the auxiliary
        // listener / Activity lifecycle callback / onUserLeaveHint forward do not leak or fire for
        // an already-disposed view.
        autoPipWiring?.dispose()
        autoPipWiring = null
        playerView.unload()
        bridgeScope.cancel()
    }
}

/**
 * Retains + tears down one view's auto-PiP wiring (flutter-android-auto-pip-entry). [listener] is
 * held strongly here because core's `addEventListener` keeps only a WEAK reference.
 *
 * [armedAutoEnter] (android-bridge-auto-pip-disarm-on-dispose-core): whether `installAutoPip`'s
 * API 31+ `setAutoEnterEnabled(true)` write actually landed on [activity]. Auto-enter is a property
 * of the ACTIVITY and outlives the view; before this flag existed, [dispose] left it armed, so a
 * host that closed the player and then pressed Home got its CURRENT screen (e.g. the store home
 * page — reproduced on a downstream Flutter host, Pixel 7 API 34) pushed into the PiP window.
 */
private class AutoPipWiring(
    private val view: LivebuyPlayerView,
    private val activity: Activity,
    private val token: LBListenerToken,
    @Suppress("unused") private val listener: LivebuyEventListener,
    private val lifecycleCallbacks: Application.ActivityLifecycleCallbacks,
    private val userLeaveForward: () -> Unit,
    private val modeChangeForward: (Boolean) -> Unit,
    private val armedAutoEnter: Boolean,
) {
    fun dispose() {
        view.removeEventListener(token)
        activity.application.unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
        LivebuyPiPUserLeaveHint.unregister(userLeaveForward)
        LivebuyPiPModeChangeHint.unregister(modeChangeForward)
        // Undo ONLY the bridge's own arm (never host-owned params); decision is the pure, tested
        // AutoPipPolicy.shouldDisarmOnDispose. runCatching: same failure posture as the arm write.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            AutoPipPolicy.shouldDisarmOnDispose(Build.VERSION.SDK_INT, armedAutoEnter)
        ) {
            runCatching {
                activity.setPictureInPictureParams(
                    PictureInPictureParams.Builder().setAutoEnterEnabled(false).build()
                )
            }
        }
    }
}

// MARK: - Bridge deserializers (expand-simulate-bridge-parity)
//
// Convert camelCase bridge args (Flutter MethodChannel Map<*, *>) into SDK
// model objects. product-bridge-data-core: read the FULL field set (incl.
// nested specifications / specOptions); fall back only when a field is
// absent (no more hardcoded 0/[]).

// 0/1 flag: tolerate Bool (Dart `_productToMap` round-trip) + Int (raw emit).
private fun flutterIntFlag(value: Any?): Int = when (value) {
    is Boolean -> if (value) 1 else 0
    is Number -> value.toInt()
    else -> 0
}

/** Bool — tolerate Boolean / Int 0/1; absent → [fallback] (native LBProduct default,
 *  goods-conclusion-fields spec). */
private fun flutterBoolOr(value: Any?, fallback: Boolean): Boolean = when (value) {
    is Boolean -> value
    is Number -> value.toInt() != 0
    else -> fallback
}

private fun flutterDoubleOrNull(value: Any?): Double? = (value as? Number)?.toDouble()

// `originalPrice`: absent/null/0 → null ("no original price").
private fun flutterOriginalPrice(value: Any?): Double? =
    flutterDoubleOrNull(value)?.takeIf { it != 0.0 }

@Suppress("UNCHECKED_CAST")
private fun flutterStringList(value: Any?): List<String> =
    (value as? List<*>)?.map { it?.toString() ?: "" } ?: emptyList()

// MARK: - Bridge serializer (vod-narrating-products-core-flutter DRY extraction)
//
// Serialize a full LBProduct to the Flutter bridge wire map (camelCase keys, same
// shape as the existing `productTap` event). Extracted from the former inline body
// of `onProductTap` so the `products` wire key on `playbackProgress` (above)
// reuses the EXACT SAME field set instead of drifting (mirrors the RN Android
// bridge's `productToMap`/`productsArray` precedent) — no behavior change to the
// existing `productTap` event. `originalPrice`/`videoId` are conditionally
// included (absent → key omitted), identical to the code this was moved from.

private fun productToMap(product: LBProduct): Map<String, Any?> {
    val payload = mutableMapOf<String, Any?>(
        "id" to product.id.toString(),
        "goodsNo" to product.goodsNo,
        "name" to product.name,
        "price" to product.price,
        "priceShow" to product.priceShow,
        "originalPriceShow" to product.originalPriceShow,
        "stock" to product.stock,
        "pic" to product.pic,
        "photos" to product.photos,
        "brief" to product.brief,
        // add-product-description-core-flutter: camelCase key, always present
        // (possibly ""), parallel to `brief`.
        "description" to product.description,
        "goodsGpn" to product.goodsGpn,
        "soldOut" to product.soldOut,
        "isHot" to product.isHot,
        "isOutSoon" to product.isOutSoon,
        "narrateStatus" to product.narrateStatus,
        // Goods conclusion fields (goods-conclusion-fields spec; native
        // LBProduct has these as defaulted props, 1f5c730).
        "canView" to product.canView,
        "canBuy" to product.canBuy,
        "isNarrating" to product.isNarrating,
        "needLabel" to product.needLabel,
        "label" to product.label,
        "isAwait" to product.isAwait,
        "isAwaitNotice" to product.isAwaitNotice,
        "beginTime" to product.beginTime,
        "endTime" to product.endTime,
        "diversionUrl" to product.diversionUrl,
        "specifications" to product.specifications.map { spec ->
            mapOf(
                "id" to spec.id,
                "name" to spec.name,
                "specificationNo" to spec.specificationNo,
                "price" to spec.price,
                "priceShow" to spec.priceShow,
                "originalPrice" to spec.originalPrice,
                "originalPriceShow" to spec.originalPriceShow,
                "stock" to spec.stock,
                "photos" to spec.photos,
            )
        },
        "specOptions" to product.specOptions.map { opt ->
            mapOf("name" to opt.name, "child" to opt.child)
        },
    )
    product.originalPrice?.takeIf { it != 0.0 }?.let { payload["originalPrice"] = it }
    // add-product-video-id-core-flutter: cross-video product reference
    // (other_goods[] only). null (goods[] items) → key omitted, camelCase
    // per design D1, same conditional-put convention as originalPrice above.
    product.videoId?.let { payload["videoId"] = it }
    return payload
}

// replay-chat-revealed-seam-core-flutter — serialize an LBComment to the Flutter bridge
// wire map for the `replayChatRevealed` event (mirrors `productToMap` above). Originally
// scoped to EXACTLY the 6 fields this seam's spec contract enumerates (`text` / `name` /
// `color` / `reply` / `reply_color` / `time`, matching the existing `CHAT_HISTORY_LOADED`
// comment wire shape's field naming) — NOT the native SDK's full 8-field `LBComment` data
// class. fix-flutter-comment-kind-wire-priority-core adds one more key, `kind`, sourced
// from the native SDK's already-resolved `LBMessageKind.rawValue` (wire-`kind`-priority-
// with-`name`/`reply`-fallback already applied natively); `isTop` remains omitted, no
// known consumer.
private fun commentToMap(c: LBComment): Map<String, Any> = mapOf(
    "text" to c.text,
    "name" to c.name,
    "color" to c.color,
    "reply" to c.reply,
    "reply_color" to c.replyColor,
    "time" to c.time,
    "kind" to c.kind.rawValue,
)

// player-moment-fields-bridge-core-flutter — serialize LBNavItem/LBHotItem to the Flutter
// bridge wire map for the `momentStateChange` event (mirrors `productToMap`'s style). `internal`
// (not `private`) so `MomentFieldsBridge.payload(...)` — a separate file in this same package/
// module — can call them: Kotlin's top-level `private` is FILE-scoped, not package-scoped, so a
// `private` declaration here would be invisible from `MomentFieldsBridge.kt`.
internal fun navItemToMap(item: LBNavItem): Map<String, Any?> {
    val body = mutableMapOf<String, Any?>(
        "id" to item.id,
        "cover" to item.cover,
        "duration" to item.duration,
        "shopName" to item.shopName,
        "preview" to item.preview,
    )
    // `title` omitted entirely when null (mirrors iOS's `lbNavItemToBody`'s `if let`
    // omit-when-nil convention, design D6) — NOT present with an explicit null value.
    item.title?.let { body["title"] = it }
    return body
}

internal fun hotItemToMap(item: LBHotItem): Map<String, Any?> = mapOf(
    "id" to item.id,
    "cover" to item.cover,
    "title" to item.title,
    "duration" to item.duration,
    "preview" to item.preview,
)

private fun lbProductFrom(map: Map<*, *>?): LBProduct? {
    // core `LBProduct.id: String` (7468cba6, cross-platform parity; JS Number-precision
    // risk). Read the raw String — do NOT `toIntOrNull()` (that produced an Int, a type
    // mismatch against the String constructor param → blocked `:livebuy_flutter:compileDebugKotlin`).
    // Aligned with same-file `lbSpecFrom`/`lbHotItemFrom`/`lbWinnerFrom` + RN's
    // `lbProductFromMap` (flutter-android-bridge-drift-fix, mirrors rn-android-bridge-drift-fix-core).
    val id = map?.get("id") as? String ?: return null
    return LBProduct(
        id = id,
        goodsNo = map["goodsNo"] as? String ?: "",
        goodsGpn = map["goodsGpn"] as? String ?: "",
        name = map["name"] as? String ?: "",
        price = flutterDoubleOrNull(map["price"]) ?: 0.0,
        priceShow = map["priceShow"] as? String ?: "",
        originalPrice = flutterOriginalPrice(map["originalPrice"]),
        originalPriceShow = map["originalPriceShow"] as? String ?: "",
        stock = (map["stock"] as? Number)?.toInt() ?: 0,
        pic = map["pic"] as? String ?: "",
        photos = flutterStringList(map["photos"]),
        brief = map["brief"] as? String ?: "",
        // add-product-description-core-flutter: reverse path for simulate* test hooks,
        // same missing-key-tolerant style as `brief` (Kotlin named args, no order
        // constraint).
        description = map["description"] as? String ?: "",
        soldOut = flutterIntFlag(map["soldOut"]),
        isHot = flutterIntFlag(map["isHot"]),
        isOutSoon = flutterIntFlag(map["isOutSoon"]),
        narrateStatus = (map["narrateStatus"] as? Number)?.toInt() ?: 0,
        // Goods conclusion fields (goods-conclusion-fields spec): bool-tolerant,
        // absent → native LBProduct's defaulted value (1f5c730).
        canView = flutterBoolOr(map["canView"], true),
        canBuy = flutterBoolOr(map["canBuy"], true),
        isNarrating = flutterBoolOr(map["isNarrating"], false),
        needLabel = flutterBoolOr(map["needLabel"], false),
        label = map["label"] as? String ?: "",
        isAwait = flutterIntFlag(map["isAwait"]),
        isAwaitNotice = flutterIntFlag(map["isAwaitNotice"]),
        beginTime = (map["beginTime"] as? Number)?.toInt(),
        endTime = (map["endTime"] as? Number)?.toInt(),
        diversionUrl = map["diversionUrl"] as? String ?: "",
        specifications = (map["specifications"] as? List<*>)
            ?.mapNotNull { lbSpecFrom(it as? Map<*, *>) } ?: emptyList(),
        specOptions = (map["specOptions"] as? List<*>)
            ?.mapNotNull { opt ->
                (opt as? Map<*, *>)?.let {
                    LBSpecOption(
                        name = it["name"] as? String ?: "",
                        child = flutterStringList(it["child"]),
                    )
                }
            } ?: emptyList(),
        // add-product-video-id-core-flutter: reverse path for simulate* test
        // hooks; missing key → null (same "as? String" tolerant convention as
        // the other optional fields above).
        videoId = map["videoId"] as? String,
    )
}

private fun lbWinnerFrom(map: Map<*, *>?): LBWinner? {
    val id = map?.get("id") as? String ?: return null
    val awardMap = map["award"] as? Map<*, *>
    val award = LBAward(
        type = awardMap?.get("type") as? String ?: "",
        code = awardMap?.get("code") as? String ?: "",
        name = awardMap?.get("name") as? String ?: "",
    )
    return LBWinner(
        id = id,
        eventId = (map["eventId"] as? Int) ?: 0,
        title = map["title"] as? String ?: "",
        award = award,
    )
}

private fun lbSpecFrom(map: Map<*, *>?): LBSpec? {
    val id = map?.get("id") as? String ?: return null
    // product-bridge-data-core: full LBSpec field set from camelCase map.
    return LBSpec(
        id = id,
        name = map["name"] as? String ?: "",
        specificationNo = map["specificationNo"] as? String ?: "",
        price = flutterDoubleOrNull(map["price"]) ?: 0.0,
        priceShow = map["priceShow"] as? String ?: "",
        originalPrice = flutterOriginalPrice(map["originalPrice"]),
        originalPriceShow = map["originalPriceShow"] as? String ?: "",
        stock = (map["stock"] as? Number)?.toInt() ?: 0,
        photos = flutterStringList(map["photos"]),
    )
}

private fun lbHotItemFrom(map: Map<*, *>?): LBHotItem? {
    val id = map?.get("id") as? String ?: return null
    // duration is a formatted string (e.g. "38:36"); watchNum NOT in model
    // (CLAUDE.md invariant: not present in API hot[] response).
    return LBHotItem(
        id = id,
        cover = map["cover"] as? String ?: "",
        title = map["title"] as? String ?: "",
        duration = map["duration"] as? String ?: "00:00",
    )
}
