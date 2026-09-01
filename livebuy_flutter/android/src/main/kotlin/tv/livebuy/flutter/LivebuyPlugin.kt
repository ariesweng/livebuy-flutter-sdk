package tv.livebuy.flutter

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import tv.livebuy.sdk.LivebuySDK
import tv.livebuy.sdk.core.LBEnvironment
import tv.livebuy.sdk.core.config.SDKConfig
import tv.livebuy.sdk.events.LBCartResultCallback
import tv.livebuy.sdk.events.LBEvent
import tv.livebuy.sdk.events.LBShareContext
import tv.livebuy.sdk.events.LivebuyEventListener
import tv.livebuy.sdk.models.LBCheckoutItem
import tv.livebuy.sdk.models.LBError
import tv.livebuy.sdk.models.LBUser
import tv.livebuy.sdk.models.LBVideoItem

class LivebuyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var appContext: Context
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pluginScope = CoroutineScope(Dispatchers.IO)

    // flutter-android-auto-pip-entry — the host Activity, needed so the player view can arm OS
    // auto-PiP + call PiPHelper.enterPiP. Unlike RN's ReactApplicationContext.currentActivity, a
    // Flutter FlutterPlugin does not natively hold an Activity; we track it via ActivityAware.
    // The player view factory reads it through the `{ currentActivity }` provider at view-create
    // time (a closure, not a snapshot) so a config-change-recreated Activity is always current.
    private var currentActivity: Activity? = null

    private companion object {
        private val SYNC_INTERCEPTOR_EVENTS = setOf(
            LBEvent.AUTH_REQUIRED,
            LBEvent.PRODUCT_CLICK,
            LBEvent.INFO_CUSTOMER_SERVICE,
            LBEvent.VIDEO_SHARE_REQUEST,
            // flutter-sync-interceptor-events-parity: mirror the native EventTypeRegistry (9 events).
            LBEvent.DISMISS_REQUEST,
            LBEvent.SERVICE_LINK_REQUEST,
            LBEvent.GUEST_NAME_EDIT_REQUEST,
            LBEvent.EVENT_JOIN_INTENT,
            LBEvent.AWARD_CLAIM_INTENT,
        )
    }

    // SDK → MethodChannel listener (installed on registerListener).
    private val sdkListener = object : LivebuyEventListener {
        override fun onEventTriggered(
            eventName: String,
            params: Map<String, Any>,
            cartCallback: LBCartResultCallback?,
            shareContext: LBShareContext?
        ): Boolean {
            val payload = mutableMapOf<String, Any?>(
                "eventName" to eventName,
                "params" to params,
            )
            if (shareContext != null) {
                payload["shareContext"] = mapOf(
                    "defaultUrl" to shareContext.shareUrl,
                    "defaultTitle" to shareContext.title,
                )
            }

            // MethodChannel.invokeMethod must run on the main thread.
            mainHandler.post {
                methodChannel.invokeMethod("onSdkEvent", payload, object : Result {
                    override fun success(result: Any?) {
                        val map = (result as? Map<*, *>) ?: return
                        handleListenerReply(eventName, map, cartCallback)
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        // Listener crashed in Dart — treat as no-op; SDK falls back to default UI.
                    }

                    override fun notImplemented() {
                        // Dart side has not installed onSdkEvent handler yet.
                    }
                })
            }

            // Cart return value is unused (SDK waits on cartCallback). Notifications ignore the return.
            // Sync interceptors: assume Dart handles since listener is registered. Cf. the same trade-off in the RN bridge.
            return SYNC_INTERCEPTOR_EVENTS.contains(eventName)
        }
    }

    private fun handleListenerReply(
        eventName: String,
        reply: Map<*, *>,
        cartCallback: LBCartResultCallback?
    ) {
        if (cartCallback != null) {
            val status = reply["status"] as? String
            when (status) {
                "success" -> {
                    val code = reply["appTrackCode"] as? String ?: ""
                    cartCallback.onSuccess(code)
                }
                "failure" -> {
                    val code = reply["errorCode"] as? String ?: "unknown"
                    val msg = reply["msg"] as? String ?: ""
                    cartCallback.onFailure(code, msg)
                }
                // else: leave to SDK's 5s timeout to fire expire()
            }
        }
        // Share-context override: writes back to the underlying shareContext for SDK to read.
        // (No-op on Android for now — the share sheet uses the values it captured at dispatch time.)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "tv.livebuy/sdk")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "tv.livebuy/player_events")
        eventChannel.setStreamHandler(LivebuyEventHandler)

        binding.platformViewRegistry.registerViewFactory(
            "LivebuyPlayerView",
            // flutter-android-auto-pip-entry — pass a live provider of the host Activity so each
            // LivebuyFlutterPlayerView can wire built-in OS auto-PiP entry (arm + consume
            // PIP_STATE_CHANGE). The closure reads `currentActivity` at view-create time.
            LivebuyPlayerViewFactory(binding.binaryMessenger, appContext) { currentActivity }
        )
        // Widget / FloatingWidget (expand-simulate-bridge-parity Tier 2)
        binding.platformViewRegistry.registerViewFactory(
            "LivebuyWidgetView",
            LivebuyWidgetViewFactory(binding.binaryMessenger)
        )
        binding.platformViewRegistry.registerViewFactory(
            "LivebuyFloatingWidgetView",
            LivebuyFloatingWidgetViewFactory(binding.binaryMessenger)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        LivebuySDK.setEventListener(null)
    }

    // MARK: - ActivityAware (flutter-android-auto-pip-entry)
    //
    // Track the host Activity so the player view can arm OS auto-PiP and call PiPHelper.enterPiP.
    // Set on attach / reattach; cleared on detach (a null Activity → the view safely skips arming,
    // no crash). PiP wiring itself lives per-view in LivebuyFlutterPlayerView.

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        currentActivity = null
    }

    override fun onDetachedFromActivity() {
        currentActivity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> {
                val apiKey: String = call.argument("apiKey") ?: ""
                val secret: String = call.argument("secret") ?: ""
                val shopId: String = call.argument("shopId")
                    ?: return result.error("BAD_ARG", "shopId required", null)
                val lang: String? = call.argument("lang")
                val displayName: String? = call.argument("displayName")
                val avatarUrl: String? = call.argument("avatarUrl")
                val externalUserId: String? = call.argument("externalUserId")
                val autoPipOnIntercept: Boolean = call.argument("autoPipOnIntercept") ?: true
                val apiVersion: Int = (call.argument<Number?>("apiVersion"))?.toInt() ?: 1
                val configFetchTimeoutMs: Int = (call.argument<Number?>("configFetchTimeoutMs"))?.toInt() ?: 5000
                val enableConversionAttribution: Boolean = call.argument("enableConversionAttribution") ?: false
                // power-profile-adaptation (Flutter parity 第 6 支): opt-OUT, default true.
                val enablePowerProfileAdaptation: Boolean = call.argument("enablePowerProfileAdaptation") ?: true
                // sdk-stat-reporting (stat-reporting-default-on-core): opt-OUT, default true.
                val enableStatReporting: Boolean = call.argument("enableStatReporting") ?: true
                // sdk-stat-endpoint-environment-selection-core + android-data-api-environment-selection-core:
                // SDK-wide environment selector forwarded as a wire string; unknown / missing → PRODUCTION.
                // Native selects BOTH the data API base URL and the /stat endpoint; Dart resolves no URL.
                val environment: LBEnvironment =
                    if (call.argument<String?>("environment") == "develop") LBEnvironment.DEVELOP
                    else LBEnvironment.PRODUCTION
                val user = if (displayName != null || avatarUrl != null || externalUserId != null)
                    LBUser(displayName = displayName ?: "", avatarUrl = avatarUrl, externalUserId = externalUserId)
                else null
                pluginScope.launch {
                    try {
                        LivebuySDK.configure(
                            context = appContext,
                            apiKey = apiKey,
                            secret = secret,
                            shopId = shopId,
                            apiVersion = apiVersion,
                            lang = lang,
                            user = user,
                            autoPipOnIntercept = autoPipOnIntercept,
                            configFetchTimeoutMs = configFetchTimeoutMs,
                            enableConversionAttribution = enableConversionAttribution,
                            enablePowerProfileAdaptation = enablePowerProfileAdaptation,
                            enableStatReporting = enableStatReporting,
                            environment = environment,
                        )
                        mainHandler.post { result.success(null) }
                    } catch (e: LBError.NotConfigured) {
                        mainHandler.post {
                            result.error("NOT_CONFIGURED", "HMAC / apiKey rejected", null)
                        }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("CONFIGURE_ERROR", t.message ?: "configure failed", null)
                        }
                    }
                }
            }

            "getSdkConfig" -> {
                try {
                    result.success(serializeSdkConfig(LivebuySDK.sdkConfig))
                } catch (e: LBError.NotConfigured) {
                    result.error("NOT_CONFIGURED", "configure() not called", null)
                }
            }

            "refreshConfig" -> {
                pluginScope.launch {
                    try {
                        LivebuySDK.refreshConfig()
                        mainHandler.post { result.success(null) }
                    } catch (e: LBError.NotConfigured) {
                        mainHandler.post {
                            result.error("NOT_CONFIGURED", "configure() not called", null)
                        }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("REFRESH_ERROR", t.message ?: "refresh failed", null)
                        }
                    }
                }
            }

            "registerListener" -> {
                LivebuySDK.setEventListener(sdkListener)
                result.success(null)
            }
            "unregisterListener" -> {
                LivebuySDK.setEventListener(null)
                result.success(null)
            }

            "setUser" -> {
                val displayName: String = call.argument("displayName")
                    ?: return result.error("BAD_ARG", "displayName required", null)
                val avatarUrl: String? = call.argument("avatarUrl")
                val externalUserId: String? = call.argument("externalUserId")
                LivebuySDK.setUser(LBUser(displayName, avatarUrl, externalUserId))
                result.success(null)
            }
            "clearUser" -> {
                LivebuySDK.clearUser()
                result.success(null)
            }

            // MARK: - Conversion attribution bridge (conversion-attribution-context-flutter)

            "captureAdClick" -> {
                val url: String? = call.argument("url")
                if (url != null) LivebuySDK.captureAdClick(url)
                result.success(null)
            }
            "setFbclid" -> {
                val fbclid: String? = call.argument("fbclid")
                if (fbclid != null) LivebuySDK.setFbclid(fbclid)
                result.success(null)
            }
            "setReferer" -> {
                LivebuySDK.setReferer(call.argument("referer"))
                result.success(null)
            }
            "clearAttributionContext" -> {
                LivebuySDK.clearAttributionContext()
                result.success(null)
            }

            // MARK: - Stat reporting bridge (sdk-stat-reporting / flutter-stat-reporting-core)

            "clearStatContext" -> {
                LivebuySDK.clearStatContext()
                result.success(null)
            }
            "currentFbc" -> {
                result.success(LivebuySDK.currentFbc())
            }
            "currentFbp" -> {
                result.success(LivebuySDK.currentFbp())
            }

            // MARK: - Power profile (power-profile-adaptation, Flutter parity 第 6 支)

            "currentPowerProfile" -> {
                // Send the stable wireName; Dart parses it back to LBPowerProfile.
                // Non-null: native getter returns FULL when dormant / opt-out / API<29.
                result.success(LivebuySDK.currentPowerProfile().wireName)
            }

            "isLoggedIn" -> {
                result.success(LivebuySDK.isLoggedIn)
            }

            "setGuestNickname" -> {
                val name: String = call.argument("name")
                    ?: return result.error("BAD_ARG", "name required", null)
                LivebuySDK.setGuestNickname(name)
                result.success(null)
            }
            "setLanguage" -> {
                val lang: String = call.argument("lang")
                    ?: return result.error("BAD_ARG", "lang required", null)
                LivebuySDK.setLanguage(lang)
                result.success(null)
            }
            "notifyCheckoutCompleted" -> {
                val orderId: String = call.argument("orderId")
                    ?: return result.error("BAD_ARG", "orderId required", null)
                val codes: List<String> = call.argument("sdkTrackCodes") ?: emptyList()
                val itemsRaw: List<Map<String, Any?>>? = call.argument("items")
                val items = itemsRaw?.map { m ->
                    LBCheckoutItem(
                        productId = m["productId"] as? String ?: "",
                        goodsGpn = m["goodsGpn"] as? String ?: "",
                        quantity = (m["quantity"] as? Number)?.toInt() ?: 1,
                        price = (m["price"] as? Number)?.toDouble() ?: 0.0,
                        sdkTrackCode = m["sdkTrackCode"] as? String ?: "",
                    )
                }
                LivebuySDK.notifyCheckoutCompleted(orderId, codes, items)
                result.success(null)
            }
            "flushPendingEvents" -> {
                pluginScope.launch {
                    try {
                        val flush = LivebuySDK.flushPendingEvents()
                        mainHandler.post {
                            result.success(mapOf(
                                "status" to flush.status,
                                "uploadedCount" to flush.uploadedCount,
                                "remainingCount" to flush.remainingCount,
                                "elapsedMs" to flush.elapsedMs,
                            ))
                        }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("FLUSH_ERROR", t.message, null)
                        }
                    }
                }
            }

            "fetchLatestLive" -> {
                // id required; ty OPTIONAL and omitted by default (null → core sends no ty).
                val id: String = call.argument("id") ?: ""
                val ty: String? = call.argument("ty")
                pluginScope.launch {
                    try {
                        val item: LBVideoItem? = LivebuySDK.fetchLatestLive(id, ty)
                        mainHandler.post {
                            if (item != null) {
                                result.success(serializeVideoItem(item))
                            } else {
                                result.success(null)
                            }
                        }
                    } catch (e: IllegalStateException) {
                        mainHandler.post { result.error("NOT_CONFIGURED", "configure() not called", null) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("FETCH_LATEST_LIVE_ERROR", t.message, null) }
                    }
                }
            }

            "fetchWidget" -> {
                // fetch-widget-content: id required, page optional (1). Calls the core
                // one-shot LivebuySDK.fetchWidget and flattens to the snake_case wire
                // map (camelCase video maps) that DefaultWidgetTemplate.handleWidgetSnapshot reads.
                val id: String = call.argument("id") ?: ""
                val page: Int = (call.argument<Number?>("page"))?.toInt() ?: 1
                pluginScope.launch {
                    try {
                        val response = LivebuySDK.fetchWidget(id, page)
                        val map = mutableMapOf<String, Any?>(
                            "videos" to response.videos.data.map { serializeVideoItem(it) },
                            "current_page" to response.videos.currentPage,
                            "last_page" to response.videos.lastPage,
                            "widget_color" to response.widgetColor,
                        )
                        // widget_bgcolor: omit the key when null (bridge convention).
                        response.widgetBgcolor?.let { map["widget_bgcolor"] = it }
                        // product_card (widget-product-card-bridge-flutter): raw passthrough of the
                        // carousel card's product-card display mode (below / inside / hidden). null →
                        // omit the whole key, same convention as widget_bgcolor above. NEVER substitute
                        // the backend default "inside" here — "backend did not send it" (linetv branch)
                        // and "backend explicitly sent inside" are two different facts, and flattening
                        // them here would leave the Dart host unable to tell them apart. Applying a
                        // default is the UI layer's job.
                        response.productCard?.let { map["product_card"] = it }
                        mainHandler.post { result.success(map) }
                    } catch (e: IllegalStateException) {
                        mainHandler.post { result.error("NOT_CONFIGURED", "configure() not called", null) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("FETCH_WIDGET_ERROR", t.message, null) }
                    }
                }
            }

            "login" -> {
                val memberId: String = call.argument("memberId")
                    ?: return result.error("BAD_ARG", "memberId required", null)
                val memberName: String? = call.argument("memberName")
                pluginScope.launch {
                    try {
                        LivebuySDK.login(memberId, memberName)
                        mainHandler.post { result.success(null) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("LB_ERROR", t.message ?: "login failed", null) }
                    }
                }
            }

            // MARK: - bindSession / isLoggedIn (auth-bind-session-ergonomics)

            "bindSession" -> {
                val memberId: String = call.argument("memberId")
                    ?: return result.error("BAD_ARG", "memberId required", null)
                val memberName: String? = call.argument("memberName")
                val avatarUrl: String? = call.argument("avatarUrl")
                pluginScope.launch {
                    try {
                        LivebuySDK.bindSession(memberId, memberName, avatarUrl)
                        mainHandler.post { result.success(null) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("LB_ERROR", t.message ?: "bindSession failed", null) }
                    }
                }
            }

            "boundMemberId" -> {
                result.success(LivebuySDK.boundMemberId)
            }

            "addToCart" -> {
                val shopId: String = call.argument("shopId")
                    ?: return result.error("LB_ERROR", "addToCart requires shopId", null)
                val goodsId: Int? = (call.argument<Number?>("goodsId"))?.toInt()
                val num: Int? = (call.argument<Number?>("num"))?.toInt()
                val specificationId: Int? = (call.argument<Number?>("specificationId"))?.toInt()
                val ids: List<Int>? = (call.argument<List<Number>?>("ids"))?.map { it.toInt() }
                val live: Int? = (call.argument<Number?>("live"))?.toInt()
                val isLive: Int? = (call.argument<Number?>("isLive"))?.toInt()
                val isWidget: Int? = (call.argument<Number?>("isWidget"))?.toInt()
                val inDomain: Int? = (call.argument<Number?>("inDomain"))?.toInt()
                val userid: String? = call.argument("userid")
                val thirdpartyUserId: String? = call.argument("thirdpartyUserId")
                val buyingId: Int? = (call.argument<Number?>("buyingId"))?.toInt()
                val eventId: Int? = (call.argument<Number?>("eventId"))?.toInt()
                val guestName: String? = call.argument("guestName")
                val dbsc: String? = call.argument("dbsc")
                val videoId: String? = call.argument("videoId")
                pluginScope.launch {
                    try {
                        val cart = LivebuySDK.addToCart(
                            shopId = shopId,
                            goodsId = goodsId,
                            num = num,
                            specificationId = specificationId,
                            ids = ids,
                            live = live,
                            isLive = isLive,
                            isWidget = isWidget,
                            inDomain = inDomain,
                            userid = userid,
                            thirdpartyUserId = thirdpartyUserId,
                            buyingId = buyingId,
                            eventId = eventId,
                            guestName = guestName,
                            dbsc = dbsc,
                            videoId = videoId,
                        )
                        mainHandler.post {
                            val out = mutableMapOf<String, Any?>(
                                "goodsNo" to cart.goodsNo,
                                "specificationNo" to cart.specificationNo,
                                "buyNo" to cart.buyNo,
                            )
                            // addcart-track ④ — 回應含 track 時附帶（{mode, level?, fields:[{key,value}]}）；
                            // 缺 track → 維持三欄向後相容。鏡像 RN / 核心 CART_ADD_RESULT 序列化。
                            cart.track?.let { track ->
                                val trackMap = mutableMapOf<String, Any?>(
                                    "mode" to track.mode.rawValue,
                                    "fields" to track.fields.map {
                                        mapOf("key" to it.key, "value" to it.value)
                                    },
                                )
                                track.level?.let { trackMap["level"] = it }
                                out["track"] = trackMap
                            }
                            result.success(out)
                        }
                    } catch (e: LBError.CartAddDeduplicated) {
                        // cart-add-tier2-unify: a 30s 重複加購 dedupe-hit → error code
                        // `cart_add_deduplicated` so Dart maps the typed LBErrorCartAddDeduplicated
                        // (host treats it as「已加入購物車」, not a failure).
                        mainHandler.post { result.error("cart_add_deduplicated", "Add-to-cart deduplicated (already added within 30 s).", null) }
                    } catch (e: LBError.ServerError) {
                        // Convey the inner serverError code (e.g. 401 raised for an empty buy_no) as the
                        // error code so the Dart `LivebuySDK.addToCart` can surface the typed LBErrorServer
                        // and branch needs-login (401) vs failure (cart-needs-login-vs-failure).
                        mainHandler.post { result.error(e.code.toString(), e.message ?: "addToCart failed", null) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("LB_ERROR", t.message ?: "addToCart failed", null) }
                    }
                }
            }

            // addcart-track ④ — token 平台結帳前回報 cart token (POST /sdk/video/addcart/track).
            "reportCartTrack" -> {
                val shopId: String = call.argument("shopId")
                    ?: return result.error("BAD_ARG", "shopId required", null)
                val buyNo: String = call.argument("buyNo")
                    ?: return result.error("BAD_ARG", "buyNo required", null)
                val trackId: String = call.argument("trackId")
                    ?: return result.error("BAD_ARG", "trackId required", null)
                pluginScope.launch {
                    try {
                        LivebuySDK.reportCartTrack(shopId = shopId, buyNo = buyNo, trackId = trackId)
                        mainHandler.post { result.success(null) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("LB_ERROR", t.message ?: "reportCartTrack failed", null) }
                    }
                }
            }

            "setAwaitGoods" -> {
                val goodsGpn: String = call.argument("goodsGpn")
                    ?: return result.error("BAD_ARG", "goodsGpn required", null)
                val enabled: Boolean = call.argument("enabled") ?: false
                pluginScope.launch {
                    try {
                        LivebuySDK.setAwaitGoods(goodsGpn, enabled)
                        mainHandler.post { result.success(null) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("LB_ERROR", t.message ?: "setAwaitGoods failed", null) }
                    }
                }
            }

            "setNoticeGoods" -> {
                val goodsGpn: String = call.argument("goodsGpn")
                    ?: return result.error("BAD_ARG", "goodsGpn required", null)
                val enabled: Boolean = call.argument("enabled") ?: false
                pluginScope.launch {
                    try {
                        LivebuySDK.setNoticeGoods(goodsGpn, enabled)
                        mainHandler.post { result.success(null) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("LB_ERROR", t.message ?: "setNoticeGoods failed", null) }
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun serializeVideoItem(item: LBVideoItem): Map<String, Any?> = mapOf(
        "id" to item.id,
        "type" to item.type,
        "title" to item.title,
        "sessionName" to item.sessionName,
        "cover" to item.cover,
        "preview" to item.preview,
        "duration" to item.duration,
        "publishAt" to item.publishAt,
        "watchNum" to item.watchNum,
        "pvNum" to item.pvNum,
        "liveStatus" to item.liveStatus,
        "pin" to item.pin,
        "showPvNum" to item.showPvNum,
        "liveurl" to item.liveurl,
        "playbackurl" to item.playbackurl,
        "previewTime" to item.previewTime,
        "showStock" to item.showStock,
    )

    private fun serializeSdkConfig(config: SDKConfig): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>("schemaVersion" to config.schemaVersion)
        out["visibility"] = config.visibility?.let { v ->
            mapOf(
                "chat" to v.chat,
                "productOverlay" to v.productOverlay,
                "activityNotification" to v.activityNotification,
                "endScreen" to v.endScreen,
                "videoInfoPanel" to v.videoInfoPanel,
            )
        }
        out["theme"] = config.theme?.let { t ->
            mapOf(
                "primaryColor" to t.primaryColor,
                "fontScale" to t.fontScale?.toDouble(),
            )
        }
        out["behavior"] = config.behavior?.let { emptyMap<String, Any?>() }
        out["layout"] = config.layout?.let { l ->
            mapOf("player" to l.player, "widget" to l.widget)
        }
        out["extensions"] = config.extensions
        return out
    }
}

// MARK: - Event sink for player callbacks

// object (singleton) because EventChannel.setStreamHandler is called once; all player views share this sink.
object LivebuyEventHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun emit(payload: Map<String, Any?>) {
        eventSink?.success(payload)
    }
}
