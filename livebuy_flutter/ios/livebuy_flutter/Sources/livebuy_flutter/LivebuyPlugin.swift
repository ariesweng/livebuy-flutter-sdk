import Flutter
import UIKit
import LivebuySDK

public final class LivebuyPlugin: NSObject, FlutterPlugin {

    private static var methodChannel: FlutterMethodChannel?
    private static var bridgeListener: BridgeListener?

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Method channel — SDK-level calls (configure / setUser / setLanguage / etc.)
        let methodChannel = FlutterMethodChannel(
            name: "tv.livebuy/sdk",
            binaryMessenger: registrar.messenger()
        )
        let instance = LivebuyPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        Self.methodChannel = methodChannel

        // Event channel — player events (state / product / poll / error)
        let eventChannel = FlutterEventChannel(
            name: "tv.livebuy/player_events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(LivebuyEventHandler.shared)

        // Native view factories
        registrar.register(
            LivebuyPlayerViewFactory(messenger: registrar.messenger()),
            withId: "LivebuyPlayerView"
        )
        // Widget / FloatingWidget (expand-simulate-bridge-parity Tier 2)
        registrar.register(
            LivebuyWidgetViewFactory(messenger: registrar.messenger()),
            withId: "LivebuyWidgetView"
        )
        registrar.register(
            LivebuyFloatingWidgetViewFactory(messenger: registrar.messenger()),
            withId: "LivebuyFloatingWidgetView"
        )
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "configure":
            let apiKey = args?["apiKey"] as? String ?? ""
            let secret = args?["secret"] as? String ?? ""
            guard let shopId = args?["shopId"] as? String, !shopId.isEmpty else {
                return result(FlutterError(code: "BAD_ARG", message: "shopId required", details: nil))
            }
            let lang = args?["lang"] as? String
            let displayName = args?["displayName"] as? String
            let avatarUrl = args?["avatarUrl"] as? String
            let externalUserId = args?["externalUserId"] as? String
            let autoPip = args?["autoPipOnIntercept"] as? Bool ?? true
            let apiVersion = args?["apiVersion"] as? Int ?? 1
            let configFetchTimeoutMs = args?["configFetchTimeoutMs"] as? Int ?? 5000
            let enableConversionAttribution = args?["enableConversionAttribution"] as? Bool ?? false
            // power-profile-adaptation (Flutter parity 第 6 支): opt-OUT, default true.
            let enablePowerProfileAdaptation = args?["enablePowerProfileAdaptation"] as? Bool ?? true
            // sdk-stat-reporting (stat-reporting-default-on-core): opt-OUT, default true.
            let enableStatReporting = args?["enableStatReporting"] as? Bool ?? true
            // sdk-stat-endpoint-environment-selection-core + sdk-data-api-environment-selection-core:
            // SDK-wide environment selector forwarded as a wire string; unknown / missing → .production.
            // Native selects BOTH the data API base URL and the /stat endpoint; Dart resolves no URL.
            let environment: LBEnvironment = (args?["environment"] as? String) == "develop" ? .develop : .production
            let user: LBUser? = (displayName != nil || avatarUrl != nil || externalUserId != nil)
                ? LBUser(displayName: displayName ?? "", avatarUrl: avatarUrl, externalUserId: externalUserId)
                : nil
            Task {
                do {
                    try await Livebuy.configure(
                        apiKey: apiKey, secret: secret, shopId: shopId, lang: lang, user: user,
                        autoPipOnIntercept: autoPip, apiVersion: apiVersion,
                        configFetchTimeoutMs: configFetchTimeoutMs,
                        enableConversionAttribution: enableConversionAttribution,
                        enablePowerProfileAdaptation: enablePowerProfileAdaptation,
                        enableStatReporting: enableStatReporting,
                        environment: environment
                    )
                    DispatchQueue.main.async { result(nil) }
                } catch LBSDKError.notConfigured {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NOT_CONFIGURED", message: "HMAC / apiKey rejected", details: nil))
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "CONFIGURE_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        // MARK: - sdk-config bridge (add-sdk-config-transport, task 4.2)

        case "getSdkConfig":
            do {
                let config = try Livebuy.sdkConfig()
                result(config.toEventDict())
            } catch LBSDKError.notConfigured {
                result(FlutterError(code: "NOT_CONFIGURED", message: "configure() not called", details: nil))
            } catch {
                result(FlutterError(code: "GET_CONFIG_ERROR", message: error.localizedDescription, details: nil))
            }

        case "refreshConfig":
            Task {
                do {
                    try await Livebuy.refreshConfig()
                    DispatchQueue.main.async { result(nil) }
                } catch LBSDKError.notConfigured {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NOT_CONFIGURED", message: "configure() not called", details: nil))
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "REFRESH_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "registerListener":
            let listener = BridgeListener()
            Self.bridgeListener = listener
            Livebuy.setEventListener(listener)
            result(nil)
        case "unregisterListener":
            Livebuy.setEventListener(nil)
            Self.bridgeListener = nil
            result(nil)

        case "setUser":
            guard let displayName = args?["displayName"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "displayName required", details: nil))
            }
            let avatarUrl = args?["avatarUrl"] as? String
            let externalUserId = args?["externalUserId"] as? String
            Livebuy.setUser(LBUser(displayName: displayName, avatarUrl: avatarUrl, externalUserId: externalUserId))
            result(nil)

        case "clearUser":
            Livebuy.clearUser()
            result(nil)

        // MARK: - Conversion attribution bridge (conversion-attribution-context-flutter)

        case "captureAdClick":
            if let urlString = args?["url"] as? String, let url = URL(string: urlString) {
                Livebuy.captureAdClick(url: url)
            }
            result(nil)

        case "setFbclid":
            if let fbclid = args?["fbclid"] as? String {
                Livebuy.setFbclid(fbclid)
            }
            result(nil)

        case "setReferer":
            Livebuy.setReferer(args?["referer"] as? String)
            result(nil)

        case "clearAttributionContext":
            Livebuy.clearAttributionContext()
            result(nil)

        // MARK: - Stat reporting bridge (sdk-stat-reporting / flutter-stat-reporting-core)

        case "clearStatContext":
            Livebuy.clearStatContext()
            result(nil)

        case "currentFbc":
            result(Livebuy.currentFbc())

        case "currentFbp":
            result(Livebuy.currentFbp())

        // MARK: - Power profile (power-profile-adaptation, Flutter parity 第 6 支)

        case "currentPowerProfile":
            // Send the stable wireName; Dart parses it back to LBPowerProfile.
            // Non-null: native getter returns .full when dormant / opt-out.
            result(Livebuy.currentPowerProfile.wireName)

        case "setGuestNickname":
            guard let name = args?["name"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "name required", details: nil))
            }
            Livebuy.setGuestNickname(name)
            result(nil)

        case "setLanguage":
            guard let lang = args?["lang"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "lang required", details: nil))
            }
            Livebuy.setLanguage(lang)
            result(nil)

        case "notifyCheckoutCompleted":
            guard let orderId = args?["orderId"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "orderId required", details: nil))
            }
            let codes = args?["sdkTrackCodes"] as? [String] ?? []
            let itemsRaw = args?["items"] as? [[String: Any]]
            let items: [LBCheckoutItem]? = itemsRaw?.compactMap { dict in
                guard let pid = dict["productId"] as? String else { return nil }
                let qty = (dict["quantity"] as? Int) ?? 1
                let priceNumber: NSDecimalNumber? = (dict["price"] as? NSNumber).map {
                    NSDecimalNumber(decimal: $0.decimalValue)
                }
                let currency = dict["currency"] as? String
                return LBCheckoutItem(productId: pid, quantity: qty, price: priceNumber, currency: currency)
            }
            Livebuy.notifyCheckoutCompleted(orderId: orderId, sdkTrackCodes: codes, items: items)
            result(nil)

        case "flushPendingEvents":
            Task {
                do {
                    let flush = try await Livebuy.flushPendingEvents()
                    DispatchQueue.main.async {
                        result([
                            "status": flush.status,
                            "uploadedCount": flush.uploadedCount,
                            "remainingCount": flush.remainingCount,
                            "elapsedMs": flush.elapsedMs,
                        ])
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "FLUSH_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "fetchLatestLive":
            // id required; ty OPTIONAL and omitted by default (nil → core sends no ty).
            let id = args?["id"] as? String ?? ""
            let ty = args?["ty"] as? String
            Task {
                do {
                    if let item = try await Livebuy.fetchLatestLive(id: id, ty: ty) {
                        let map = flutterSerializeVideoItem(item)
                        DispatchQueue.main.async { result(map) }
                    } else {
                        DispatchQueue.main.async { result(nil) }
                    }
                } catch LBSDKError.notConfigured {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NOT_CONFIGURED", message: "configure() not called", details: nil))
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "FETCH_LATEST_LIVE_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "fetchWidget":
            // fetch-widget-content: id required, page optional (1). Calls the core
            // one-shot Livebuy.fetchWidget and flattens to the snake_case wire map
            // (camelCase video maps) that DefaultWidgetTemplate.handleWidgetSnapshot reads.
            let id = args?["id"] as? String ?? ""
            let page = (args?["page"] as? Int) ?? 1
            Task {
                do {
                    let response = try await Livebuy.fetchWidget(id: id, page: page)
                    var map: [String: Any] = [
                        "videos": response.videos.data.map { flutterSerializeVideoItem($0) },
                        "current_page": response.videos.currentPage,
                        "last_page": response.videos.lastPage,
                        "widget_color": response.widgetColor,
                    ]
                    if let bgcolor = response.widgetBgcolor { map["widget_bgcolor"] = bgcolor }
                    // product_card (widget-product-card-bridge-flutter): raw passthrough of the
                    // carousel card's product-card display mode (below / inside / hidden). nil →
                    // omit the whole key, same convention as widget_bgcolor above. NEVER substitute
                    // the backend default "inside" here — "backend did not send it" (linetv branch)
                    // and "backend explicitly sent inside" are two different facts, and flattening
                    // them here would leave the Dart host unable to tell them apart. Applying a
                    // default is the UI layer's job.
                    if let productCard = response.productCard { map["product_card"] = productCard }
                    DispatchQueue.main.async { result(map) }
                } catch LBSDKError.notConfigured {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NOT_CONFIGURED", message: "configure() not called", details: nil))
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "FETCH_WIDGET_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        // MARK: - login (login-session-token-core)

        case "login":
            guard let memberId = args?["memberId"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "memberId required", details: nil))
            }
            let memberName = args?["memberName"] as? String
            Task {
                do {
                    try await Livebuy.login(memberId: memberId, memberName: memberName)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "LB_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        // MARK: - bindSession / isLoggedIn (auth-bind-session-ergonomics)

        case "bindSession":
            guard let memberId = args?["memberId"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "memberId required", details: nil))
            }
            let memberName = args?["memberName"] as? String
            let avatarUrl = args?["avatarUrl"] as? String
            Task {
                do {
                    try await Livebuy.bindSession(memberId: memberId, memberName: memberName, avatarUrl: avatarUrl)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "LB_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "isLoggedIn":
            result(Livebuy.isLoggedIn)

        case "boundMemberId":
            result(Livebuy.boundMemberId)

        // MARK: - addToCart (video-addcart-endpoint-core, 路線 B)

        case "addToCart":
            guard let shopId = args?["shopId"] as? String else {
                return result(FlutterError(code: "LB_ERROR", message: "addToCart requires shopId", details: nil))
            }
            let goodsId = args?["goodsId"] as? Int
            let num = args?["num"] as? Int
            let specificationId = args?["specificationId"] as? Int
            let ids = args?["ids"] as? [Int]
            let live = args?["live"] as? Int
            let isLive = args?["isLive"] as? Int
            let isWidget = args?["isWidget"] as? Int
            let inDomain = args?["inDomain"] as? Int
            let userid = args?["userid"] as? String
            let thirdpartyUserId = args?["thirdpartyUserId"] as? String
            let buyingId = args?["buyingId"] as? Int
            let eventId = args?["eventId"] as? Int
            let guestName = args?["guestName"] as? String
            let dbsc = args?["dbsc"] as? String
            let videoId = args?["videoId"] as? String
            Task {
                do {
                    let cart = try await Livebuy.addToCart(
                        shopId: shopId, goodsId: goodsId, num: num,
                        specificationId: specificationId, ids: ids,
                        live: live, isLive: isLive, isWidget: isWidget,
                        inDomain: inDomain, userid: userid,
                        thirdpartyUserId: thirdpartyUserId, buyingId: buyingId,
                        eventId: eventId, guestName: guestName, dbsc: dbsc,
                        videoId: videoId)
                    DispatchQueue.main.async {
                        var out: [String: Any] = [
                            "goodsNo": cart.goodsNo,
                            "specificationNo": cart.specificationNo,
                            "buyNo": cart.buyNo,
                        ]
                        // addcart-track ④ — 回應含 track 時附帶（{mode, level?, fields:[{key,value}]}）；
                        // 缺 track → 維持三欄向後相容。鏡像 RN / 核心 CART_ADD_RESULT 序列化。
                        if let track = cart.track {
                            var trackDict: [String: Any] = [
                                "mode": track.mode.rawValue,
                                "fields": track.fields.map { ["key": $0.key, "value": $0.value] },
                            ]
                            if let level = track.level { trackDict["level"] = level }
                            out["track"] = trackDict
                        }
                        result(out)
                    }
                } catch let lbError as LBError {
                    // cart-add-tier2-unify: a 30s 重複加購 dedupe-hit → FlutterError code
                    // `cart_add_deduplicated` so Dart maps the typed LBErrorCartAddDeduplicated
                    // (host treats it as「已加入購物車」). serverError code (e.g. 401 for an empty
                    // buy_no) → that code so Dart branches needs-login (401) vs failure.
                    DispatchQueue.main.async {
                        if case .cartAddDeduplicated = lbError {
                            result(FlutterError(code: "cart_add_deduplicated", message: "Add-to-cart deduplicated (already added within 30 s).", details: nil))
                        } else if case .serverError(let code, let message) = lbError {
                            result(FlutterError(code: String(code), message: message, details: nil))
                        } else {
                            result(FlutterError(code: "LB_ERROR", message: lbError.localizedDescription, details: nil))
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "LB_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        // addcart-track ④ — token 平台結帳前回報 cart token (POST /sdk/video/addcart/track).
        case "reportCartTrack":
            guard let shopId = args?["shopId"] as? String,
                  let buyNo = args?["buyNo"] as? String,
                  let trackId = args?["trackId"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "reportCartTrack requires shopId/buyNo/trackId", details: nil))
            }
            Task {
                do {
                    try await Livebuy.reportCartTrack(shopId: shopId, buyNo: buyNo, trackId: trackId)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "LB_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        // MARK: - goods tracking (goods-await-notice-endpoints-core)

        case "setAwaitGoods":
            guard let goodsGpn = args?["goodsGpn"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "goodsGpn required", details: nil))
            }
            let awaitEnabled = args?["enabled"] as? Bool ?? false
            Task {
                do {
                    try await Livebuy.setAwaitGoods(goodsGpn: goodsGpn, enabled: awaitEnabled)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "LB_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "setNoticeGoods":
            guard let goodsGpn = args?["goodsGpn"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "goodsGpn required", details: nil))
            }
            let noticeEnabled = args?["enabled"] as? Bool ?? false
            Task {
                do {
                    try await Livebuy.setNoticeGoods(goodsGpn: goodsGpn, enabled: noticeEnabled)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "LB_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Internal — accessible to BridgeListener so it can invoke onSdkEvent.
    fileprivate static func dispatchToDart(
        eventName: String,
        params: [String: Any],
        shareContext: LBShareContext?,
        cartCallback: LBCartResultCallback?
    ) {
        guard let channel = methodChannel else { return }

        var payload: [String: Any] = [
            "eventName": eventName,
            "params": params,
        ]
        if let share = shareContext {
            payload["shareContext"] = [
                "defaultUrl": share.shareUrl,
                "defaultTitle": share.title,
            ]
        }

        DispatchQueue.main.async {
            channel.invokeMethod("onSdkEvent", arguments: payload) { reply in
                guard let cartCallback = cartCallback,
                      let map = reply as? [String: Any] else { return }
                let status = map["status"] as? String
                switch status {
                case "success":
                    let code = map["appTrackCode"] as? String ?? ""
                    cartCallback.onSuccess(appTrackCode: code)
                case "failure":
                    let code = map["errorCode"] as? String ?? "unknown"
                    let msg = map["msg"] as? String ?? ""
                    cartCallback.onFailure(errorCode: code, message: msg)
                default:
                    break  // SDK's 5s timer handles timeout
                }
            }
        }
    }
}

// MARK: - BridgeListener

/// Implements LivebuyEventListener and forwards every event to Dart via the SDK MethodChannel.
private final class BridgeListener: NSObject, LivebuyEventListener {
    private static let syncInterceptorEvents: Set<String> = [
        LBEvent.authRequired,
        LBEvent.productClick,
        LBEvent.infoCustomerService,
        LBEvent.videoShareRequest,
        // flutter-sync-interceptor-events-parity: mirror the native EventTypeRegistry (9 events).
        LBEvent.dismissRequest,
        LBEvent.serviceLinkRequest,
        LBEvent.guestNameEditRequest,
        LBEvent.eventJoinIntent,
        LBEvent.awardClaimIntent,
    ]

    func onEventTriggered(
        eventName: String,
        params: [String: Any],
        cartCallback: LBCartResultCallback?,
        shareContext: LBShareContext?
    ) -> Bool {
        LivebuyPlugin.dispatchToDart(
            eventName: eventName, params: params,
            shareContext: shareContext, cartCallback: cartCallback,
        )
        // Cart return value is unused (SDK waits on cartCallback). Notifications ignore the return.
        // Sync interceptors: assume Dart handles since listener is registered — same trade-off as the RN bridge.
        return BridgeListener.syncInterceptorEvents.contains(eventName)
    }
}

// MARK: - Event sink for player callbacks

final class LivebuyEventHandler: NSObject, FlutterStreamHandler {
    // Singleton because setStreamHandler is called once at registration; all views must share this one sink.
    static let shared = LivebuyEventHandler()
    private var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    func emit(_ payload: [String: Any]) {
        // FlutterEventSink must be called on the main thread; native callbacks may arrive on background threads.
        DispatchQueue.main.async { self.eventSink?(payload) }
    }
}

// MARK: - Native view factory

final class LivebuyPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return LivebuyFlutterPlayerView(frame: frame, viewId: viewId, messenger: messenger, args: args)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - FlutterPlatformView wrapping LivebuyPlayerViewController

final class LivebuyFlutterPlayerView: NSObject, FlutterPlatformView {
    private let playerVC: LivebuyPlayerViewController
    private let container: UIView
    private let methodChannel: FlutterMethodChannel

    // rb-flutter-subtitle-channel-bridge-core: last channel id we emitted a
    // `subtitleChange` payload for, so a same-channel state-machine tick
    // (loading→buffering→playing, …) does not re-emit. Reset naturally on a
    // real channel switch (see `flutterSubtitleShouldEmit`); no explicit
    // reset needed at unload/dispose.
    private var lastSubtitleChannelId: String?

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {
        playerVC = LivebuyPlayerViewController()
        container = UIView(frame: frame)

        // Channel is registered here in init (not in factory) because viewId is only available at view creation time.
        methodChannel = FlutterMethodChannel(
            name: "tv.livebuy/player_\(viewId)",
            binaryMessenger: messenger
        )

        super.init()

        playerVC.onStateChange = { [weak self] state in
            let raw: String
            switch state {
            case .loading:   raw = "loading"
            case .buffering: raw = "buffering"
            case .playing:   raw = "playing"
            case .paused:    raw = "paused"
            case .ended:     raw = "ended"
            case .error:     raw = "error"
            // MARK: - decouple-ui-from-logic sub-states
            case .awaitingLive:       raw = "awaitingLive"
            case .startScreenPlaying: raw = "startScreenPlaying"
            case .endScreenShown:     raw = "endScreenShown"
            }
            LivebuyEventHandler.shared.emit(["event": "stateChange", "state": raw])

            // rb-flutter-subtitle-channel-bridge-core: piggyback on this ALREADY-EXISTING
            // hook to read the ALREADY-PUBLIC `channel` property (no new native hook added,
            // no ios/Sources/LivebuySDK/ change). `channel` is set synchronously before
            // `configureFromChannel` runs, so it is fresh by the time any state after the
            // very first cold-start `.loading` tick fires; a still-nil channel is simply
            // skipped (self-corrects on the next tick).
            guard let self, let ch = self.playerVC.channel,
                  flutterSubtitleShouldEmit(channelId: ch.id, lastEmittedId: self.lastSubtitleChannelId)
            else { return }
            self.lastSubtitleChannelId = ch.id
            LivebuyEventHandler.shared.emit(
                flutterSubtitlePayload(isSubtitle: ch.isSubtitle, subtitleUrl: ch.subtitleUrl))
        }

        // NOTE: a `channelChange` reverse-event (lightweight LBChannel projection for
        // upcoming chrome) was hand-stubbed here against a
        // `LivebuyPlayerViewController.onChannelChange` hook that exists on NO platform
        // SDK — it never compiled. Removed (flutter-bridge-build gate). To restore, add
        // the `onChannelChange` hook to the iOS/Android SDK first (core + 4-platform
        // parity), then re-wire the emit here.

        playerVC.onProductTap = { product in
            // product-bridge-data-core: emit the full field set (camelCase
            // keys per design D1) incl. nested specifications / specOptions.
            var payload = Self.lbProductToBody(product)
            payload["event"] = "productTap"
            LivebuyEventHandler.shared.emit(payload)
        }

        playerVC.onPollReceived = { resp in
            // core-flutter-poll-params：序列化完整統一 POLL_RECEIVED params（last/push（帶 kind/reply/
            // reply_color）/user/rush/win/live_end?/top?）供 flutter-ui template 路由合流 feed 與
            // chat-message-taxonomy（narrate→browse、主播/回覆/AI 角色、置頂）。保留 `liveEnd`(camel)
            // 供 flutter/lib deprecated host callback `LBPollResponse.fromMap` 相容。
            var payload: [String: Any] = ["event": "pollReceived"]
            payload.merge(LivebuyPlayerViewController.pollReceivedEventParams(resp)) { _, new in new }
            if let liveEnd = resp.liveEnd { payload["liveEnd"] = liveEnd }
            LivebuyEventHandler.shared.emit(payload)
        }

        playerVC.onError = { error in
            var payload: [String: Any] = ["event": "error"]
            switch error {
            case .restricted:       payload["type"] = "restricted"
            case .videoNotFound:    payload["type"] = "videoNotFound"
            case .invalidSignature: payload["type"] = "invalidSignature"
            case .chatRateLimited:  payload["type"] = "chatRateLimited"
            // commentsub-checkname-contract-core §8.2: chat business errors.
            case .guestNameTaken:    payload["type"] = "guestNameTaken"
            case .chatRequiresLogin: payload["type"] = "chatRequiresLogin"
            case .notLive:           payload["type"] = "notLive"
            case .sdkVersionUnsupported:
                payload["type"] = "sdk_version_unsupported"
            case .networkError(let u):
                payload["type"] = "networkError"
                payload["message"] = u.localizedDescription
            case .serverError(let code, let msg):
                payload["type"] = "serverError"
                payload["code"] = code
                payload["message"] = msg
            case .loginFailed(let code, let msg):
                // login() surfaces failures via the method-channel error path; this
                // event mapping is a fallback. No dedicated Dart union member — map
                // to serverError.
                payload["type"] = "serverError"
                payload["code"] = code
                payload["message"] = msg
            case .sdkConfigFetchFailed(let underlying):
                // Only carried inside SDK_CONFIG_LOAD_FAILED payloads; fallback for
                // switch exhaustiveness.
                payload["type"] = "networkError"
                payload["message"] = underlying?.localizedDescription ?? "config fetch failed"
            @unknown default:
                // core LBError is a non-frozen public enum — future-proof.
                payload["type"] = "serverError"
                payload["code"] = -1
                payload["message"] = "unknown error"
            }
            LivebuyEventHandler.shared.emit(payload)
        }

        // flutter-vod-playback-progress-core — VOD-1 playback-progress forward.
        // `LivebuyPlayerViewController.onPlaybackProgressChange` already exists
        // natively (2026-06-08-vod-playback-progress-core), so this is a real
        // hook (not the reverted onChannelChange situation above).
        // vod-narrating-products-core-flutter: additive `products` wire key — the
        // raw, unfiltered `channel.goods` snapshot (same source core's own
        // `vodActiveProducts(products:position:)` reads), serialized via the same
        // `lbProductToBody(_:)` helper `onProductTap` uses. Dart independently
        // filters by `[beginTime, endTime)` + `position` (component-contracts
        // `Player（Flutter）VOD playback-progress 頻道與控制出口 — core bridge
        // parity`). `[weak self]` added (this closure did not previously capture
        // self) to read `self.playerVC.channel`, mirroring `onStateChange`'s
        // existing `[weak self]` capture for the same `channel` property.
        playerVC.onPlaybackProgressChange = { [weak self] progress in
            LivebuyEventHandler.shared.emit([
                "event": "playbackProgress",
                "position": progress.position,
                "duration": progress.duration,
                "isPlaying": progress.isPlaying,
                "isReplay": progress.isReplay,
                "products": (self?.playerVC.channel?.goods ?? []).map { Self.lbProductToBody($0) },
            ])
        }

        container.addSubview(playerVC.view)
        playerVC.view.frame = container.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }

        if let params = args as? [String: Any], let videoId = params["videoId"] as? String {
            playerVC.load(videoId: videoId)
        }
    }

    func view() -> UIView { container }

    /// Serialize a full `LBProduct` to the Flutter bridge wire dict (camelCase keys per design D1,
    /// incl. nested specifications / specOptions). Extracted from the former inline body of
    /// `onProductTap` (vod-narrating-products-core-flutter DRY refactor, mirroring the RN iOS
    /// bridge's `lbProductToBody(_:)` precedent) so the new `products` wire key on
    /// `onPlaybackProgressChange` (above) reuses the EXACT SAME wire shape as `productTap`, instead
    /// of drifting — no behavior change to the existing `productTap` event. `price` /
    /// `originalPrice` carried as the core Double value; `originalPrice == 0` → omit (no original
    /// price). `beginTime`/`endTime`/`videoId` nil → omit. Aligned field-by-field with core
    /// `LBProduct` (23 fields). Does NOT set an `"event"` key — callers add their own.
    private static func lbProductToBody(_ product: LBProduct) -> [String: Any] {
        var body: [String: Any] = [
            "id": product.id,
            "goodsNo": product.goodsNo,
            "name": product.name,
            "price": product.price,
            "priceShow": product.priceShow,
            "originalPriceShow": product.originalPriceShow,
            "stock": product.stock,
            "pic": product.pic,
            "photos": product.photos,
            "brief": product.brief,
            // add-product-description-core-flutter: camelCase key, always present
            // (possibly ""), parallel to `brief`.
            "description": product.description,
            "goodsGpn": product.goodsGpn,
            "soldOut": product.soldOut,
            "isHot": product.isHot,
            "isOutSoon": product.isOutSoon,
            "narrateStatus": product.narrateStatus,
            // Goods conclusion fields (goods-conclusion-fields spec; native
            // LBProduct has these as defaulted props, a9d13a7).
            "canView": product.canView,
            "canBuy": product.canBuy,
            "isNarrating": product.isNarrating,
            "needLabel": product.needLabel,
            "label": product.label,
            "isAwait": product.isAwait,
            "isAwaitNotice": product.isAwaitNotice,
            "diversionUrl": product.diversionUrl,
            "specifications": product.specifications.map { spec in
                [
                    "id": spec.id,
                    "name": spec.name,
                    "specificationNo": spec.specificationNo,
                    "price": spec.price,
                    "priceShow": spec.priceShow,
                    "originalPrice": spec.originalPrice as Any,
                    "originalPriceShow": spec.originalPriceShow,
                    "stock": spec.stock,
                    "photos": spec.photos,
                ]
            },
            "specOptions": product.specOptions.map { opt in
                ["name": opt.name, "child": opt.child]
            },
        ]
        if let op = product.originalPrice, op != 0 { body["originalPrice"] = op }
        if let bt = product.beginTime { body["beginTime"] = bt }
        if let et = product.endTime { body["endTime"] = et }
        // add-product-video-id-core-flutter: cross-video product reference
        // (other_goods[] only). nil (goods[] items) → key omitted, camelCase
        // per design D1, same "if let" omit-when-nil convention as
        // originalPrice/beginTime/endTime above.
        if let videoId = product.videoId { body["videoId"] = videoId }
        return body
    }

    /// Serialize an `LBActiveEvent` to the Flutter bridge wire dict — EQUIVALENT to the SDK's
    /// internal `LivebuyPlayerViewController.activeEventParams(_:)` (that helper is `internal`,
    /// so it is unreachable from this separate plugin module). Mirrors the RN iOS bridge's
    /// `activeEventBody` (active-event-accessor-flutter-core). `keyword` is OMITTED when nil or
    /// empty (「無可參加 keyword」); `stayTime` is EXCLUDED (turnkey internal dwell gate, not host
    /// UI info). `award` reuses the `{type,name,code}` winner-award structure.
    private static func activeEventBody(_ event: LBActiveEvent) -> [String: Any] {
        var body: [String: Any] = [
            "id": event.id,
            "title": event.title,
            "duration": event.duration,
            "surplus": event.surplus,
            "award": event.award.map { ["type": $0.type, "name": $0.name, "code": $0.code] },
        ]
        if let keyword = event.keyword, !keyword.isEmpty { body["keyword"] = keyword }
        return body
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "load":
            if let videoId = args?["videoId"] as? String { playerVC.load(videoId: videoId) }
            result(nil)
        // Legacy method name preserved as alias for backward compat.
        case "release":
            playerVC.unload()
            playerVC.view.removeFromSuperview()
            result(nil)
        case "unload":
            playerVC.unload()
            result(nil)
        case "play":
            playerVC.play()
            result(nil)
        case "pause":
            playerVC.pause()
            result(nil)
        case "setMuted":
            if let muted = args?["muted"] as? Bool { playerVC.setMuted(muted) }
            result(nil)
        case "seek":
            if let s = args?["seconds"] as? Double { playerVC.seek(seconds: s) }
            result(nil)
        // flutter-vod-playback-progress-core — VOD-1 control exits. Both forward
        // directly to native methods that already exist on
        // LivebuyPlayerViewController (2026-06-08-vod-playback-progress-core);
        // the gate (`vodScrubAllowed`) is enforced natively inside `seekBy(_:)`.
        case "togglePlayPause":
            playerVC.togglePlayPause()
            result(nil)
        case "seekBy":
            if let s = args?["seconds"] as? Double { playerVC.seekBy(s) }
            result(nil)
        case "sendChat":
            if let msg = args?["message"] as? String {
                let eventId = args?["eventId"] as? Int
                Task {
                    try? await playerVC.sendChat(message: msg, eventId: eventId)
                }
            }
            result(nil)

        // MARK: - New methods per spec §Player Public methods

        case "skipStart":
            playerVC.skipStart()
            result(nil)
        case "cancelAutoNext":
            playerVC.cancelAutoNext()
            result(nil)
        case "requestEventJoin":
            if let eid = args?["eid"] as? Int, let keyword = args?["keyword"] as? String {
                playerVC.requestEventJoin(eid: eid, keyword: keyword)
            }
            result(nil)
        case "requestViewCart":
            // view-cart-event-flutter-core: 查看購物車 CTA → core seam (emit VIEW_CART).
            playerVC.requestViewCart(productId: args?["productId"] as? String)
            result(nil)
        case "reportEventStay":
            // 直播抽獎停留補登（fire-and-forget；native 自行背景送出）。
            if let eventId = args?["eventId"] as? Int {
                playerVC.reportEventStay(eventId: eventId, stayTime: args?["stayTime"] as? Int)
            }
            result(nil)
        case "activeEvents":
            // active-event-accessor-flutter-core: 直播抽獎「進行中活動」唯讀快照 accessor.
            // playerVC.activeEvents() is public ([LBActiveEvent]); serialize each to the
            // Flutter bridge wire dict. The SDK's internal
            // `LivebuyPlayerViewController.activeEventParams(_:)` is NOT public (unreachable
            // from this separate plugin module), so do the equivalent serialization here
            // (mirrors the RN iOS bridge `activeEventBody`): id / title / duration / surplus /
            // award:[{type,name,code}], keyword only when non-empty, stayTime EXCLUDED
            // (turnkey internal dwell gate). No active events → empty array.
            result(playerVC.activeEvents().map { LivebuyFlutterPlayerView.activeEventBody($0) })
        case "requestAwardClaim":
            if let winnerMap = args?["winner"] as? [String: Any],
               let winner = flutterLBWinnerFromArgs(winnerMap) {
                let email = (args?["contact"] as? [String: Any])?["email"] as? String
                let input = email.map { LBAwardClaimInput(email: $0) }
                playerVC.requestAwardClaim(winner: winner, contact: input)
            }
            result(nil)

        // guest-nickname-checkname-on-set-flutter: player-scoped 已驗證暱稱設定. checkName 成功才
        // commit（持久化 + 廣播）；結果分類經 FlutterError code 表達，Dart 端表現為 PlatformException.
        //
        // guest-nickname-verified-fails-loudly-flutter: core 不再對「沒提交暱稱」的路徑靜默返回
        // （guest-nickname-verified-fails-loudly-core），所以這裡要把 PRE-FLIGHT 失敗與 checkName
        // ROUND-TRIP 失敗分開表達 — 它們是三個不同的類別，壓成一個 code 會讓 host 對「重試」做出
        // 錯誤判斷：
        //   • NICKNAME_SET_PRECONDITION_FAILED — 請求根本沒送出（名稱 trim 後為空 / 尚未 load 任何
        //     影片）。重試同樣會失敗；host 要改的是呼叫的參數或時機。
        //   • NOT_CONFIGURED — SDK 尚未 configure(...) 成功返回。初始化缺漏，同樣沒送出任何請求。
        //   • CHECKNAME_FAILED — 請求送出了、結果未定（網路 / server error）。這一類才是可重試的。
        //
        // 兩個新 catch MUST 排在泛 catch 之前 — Swift 先寫先匹配，放在後面會被 CHECKNAME_FAILED
        // 整個吞掉（且編譯器不會提醒）。
        //
        // 型別歸屬注意（lead design.md 決策 A）：`notConfigured` 屬**獨立**的 `LBSDKError`，不是
        // `LBError` 的 case，故需要第二個 catch 子句。這是 iOS core 的既有結構（Android 的
        // NotConfigured 則住在 LBError sealed class 內）；兩端型別歸屬不同、但 wire code 必須一致，
        // MUST NOT 為了讓語法對齊而新造或搬移 error 型別。
        case "setGuestNicknameVerified":
            guard let name = args?["name"] as? String else {
                return result(FlutterError(code: "BAD_ARG", message: "name required", details: nil))
            }
            Task {
                do {
                    try await playerVC.setGuestNicknameVerified(name)
                    DispatchQueue.main.async { result(nil) }
                } catch LBError.nicknameSetPreconditionFailed {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NICKNAME_SET_PRECONDITION_FAILED",
                                            message: "nickname set precondition failed (blank name, or no video loaded) — checkName was never sent",
                                            details: nil))
                    }
                } catch LBSDKError.notConfigured {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NOT_CONFIGURED",
                                            message: "LivebuySDK.configure(...) has not returned successfully yet",
                                            details: nil))
                    }
                } catch LBError.guestNameTaken {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "GUEST_NAME_TAKEN", message: "nickname already taken", details: nil))
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "CHECKNAME_FAILED", message: error.localizedDescription, details: nil))
                    }
                }
            }
        case "minimize":
            playerVC.minimize()
            result(nil)
        case "expand":
            playerVC.expand()
            result(nil)

        // MARK: - Sub-component simulate* (expand-simulate-bridge-parity)

        // These forward to the SDK's public `perform*` API (the concrete
        // sub-component views are internal — expand-simulate-bridge-parity).

        // ChatView
        case "chatView_simulateSendTap":
            if let text = args?["text"] as? String {
                let eventId = args?["eventId"] as? Int
                playerVC.performSendChat(text: text, eventId: eventId)
            }
            result(nil)
        case "chatView_simulateLoadHistoryTap":
            playerVC.performLoadChatHistory()
            result(nil)
        case "chatView_simulateEventJoinTap":
            if let eid = args?["eid"] as? Int, let keyword = args?["keyword"] as? String {
                playerVC.performJoinEvent(eid: eid, keyword: keyword)
            }
            result(nil)

        // ProductOverlayView
        case "productOverlay_simulateProductTap":
            if let map = args as? [String: Any], let p = flutterLBProductFromArgs(map) {
                playerVC.performProductTap(p)
            }
            result(nil)
        case "productOverlay_simulatePushCardDismiss":
            playerVC.performDismissPushCard()
            result(nil)
        case "productOverlay_simulatePanelToggle":
            playerVC.performToggleProductPanel()
            result(nil)

        // ProductListPanel
        case "productListPanel_simulateProductTap":
            if let map = args as? [String: Any], let p = flutterLBProductFromArgs(map) {
                playerVC.performListProductTap(p)
            }
            result(nil)
        case "productListPanel_simulateAddCart":
            if let map = args as? [String: Any],
               let pMap = map["product"] as? [String: Any],
               let p = flutterLBProductFromArgs(pMap) {
                let spec = (map["spec"] as? [String: Any]).flatMap { flutterLBSpecFromArgs($0) }
                playerVC.performAddToCart(p, selectedSpec: spec)
            }
            result(nil)
        case "productListPanel_simulateRestockNotice":
            if let map = args as? [String: Any], let p = flutterLBProductFromArgs(map) {
                playerVC.performListRestockNotice(p)
            }
            result(nil)

        // OperationPanelView
        case "operationPanel_simulateGoodsTap":          playerVC.performGoodsTap(); result(nil)
        case "operationPanel_simulateChatToggleTap":     playerVC.performChatToggle(); result(nil)
        case "operationPanel_simulateLikeTap":           playerVC.performLike(); result(nil)
        case "operationPanel_simulateShareTap":          playerVC.performShare(); result(nil)
        case "operationPanel_simulateSubtitleToggleTap": playerVC.performSubtitleToggle(); result(nil)
        case "operationPanel_simulateServiceLinkTap":    playerVC.performServiceLink(); result(nil)
        case "operationPanel_simulateMoreTap":           playerVC.performMore(); result(nil)
        case "operationPanel_simulateGuestNameEditTap":  playerVC.performGuestNameEdit(); result(nil)
        case "operationPanel_simulateSkipStartTap":      playerVC.performSkipStart(); result(nil)
        case "operationPanel_simulateBackToLiveTap":     playerVC.performBackToLive(); result(nil)

        // VideoInfoPanel
        case "videoInfoPanel_simulateSubscribeTap":      playerVC.performInfoPanelSubscribe(); result(nil)
        case "videoInfoPanel_simulateServiceLinkTap":    playerVC.performInfoPanelServiceLink(); result(nil)
        case "videoInfoPanel_simulateShopTap":           playerVC.performInfoPanelShop(); result(nil)
        case "videoInfoPanel_simulateDismiss":           playerVC.performInfoPanelDismiss(); result(nil)
        case "videoInfoPanel_simulateTabChange":
            playerVC.performInfoPanelTabChange(tab: args?["tab"] as? String ?? "info")
            result(nil)

        // EndScreenView
        case "endScreen_simulateCancelTap":
            playerVC.performEndScreenCancel()
            result(nil)
        case "endScreen_simulateHotItemTap":
            if let map = args as? [String: Any], let item = flutterLBHotItemFromArgs(map) {
                playerVC.performEndScreenHotItemTap(item)
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - Flutter bridge deserializers (expand-simulate-bridge-parity)

// product-bridge-data-core: read 0/1 flags tolerating both Bool (Dart
// `_productToMap` round-trip) and Int (raw native emit re-fed by host).
private func flutterIntFlag(_ value: Any?) -> Int {
    if let b = value as? Bool { return b ? 1 : 0 }
    if let i = value as? Int { return i }
    if let n = value as? NSNumber { return n.intValue }
    return 0
}

/// Bool — tolerate Bool, Int 0/1; absent → `fallback` (native LBProduct default,
/// goods-conclusion-fields spec).
private func flutterBoolOr(_ value: Any?, _ fallback: Bool) -> Bool {
    if let b = value as? Bool { return b }
    if let n = value as? NSNumber { return n.intValue != 0 }
    return fallback
}

private func flutterDoubleOrNil(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let n = value as? NSNumber { return n.doubleValue }
    return nil
}

// `originalPrice`: absent/0 → nil ("no original price").
private func flutterOriginalPrice(_ value: Any?) -> Double? {
    guard let d = flutterDoubleOrNil(value), d != 0 else { return nil }
    return d
}

// MARK: - Subtitle-channel bridge (rb-flutter-subtitle-channel-bridge-core)
//
// Pure helpers for the `subtitleChange` EventChannel emit — zero UIKit / Flutter
// dependency so they're a thin, easily-inspected call site from the
// `onStateChange` closure. (No XCTest target exists for this SPM package today —
// see design.md Risks; kept free-function-shaped for future testability, mirroring
// the Android bridge's `SubtitleChannelBridge` JVM-tested pure object.)

/// Dedupe gate: should we (re-)emit `subtitleChange` for `channelId`, given the
/// last id we emitted for (nil on the very first emit → always true)? Re-emits
/// exactly once per distinct loaded channel id.
func flutterSubtitleShouldEmit(channelId: String, lastEmittedId: String?) -> Bool {
    channelId != lastEmittedId
}

/// Builds the `subtitleChange` EventChannel payload. `isSubtitle` is the raw
/// native Int flag (0/1); `available` on the wire is the Bool it decodes to.
func flutterSubtitlePayload(isSubtitle: Int, subtitleUrl: String) -> [String: Any] {
    ["event": "subtitleChange", "available": isSubtitle == 1, "url": subtitleUrl]
}

private func flutterLBProductFromArgs(_ map: [String: Any]) -> LBProduct? {
    guard let id = map["id"] as? String else { return nil }
    // product-bridge-data-core: read the full field set from the camelCase
    // bridge map; fall back only when absent (no more hardcoded 0/[]).
    // Build via the core memberwise init (core LBProduct is not Decodable).
    return LBProduct(
        id: id,
        goodsNo: map["goodsNo"] as? String ?? "",
        goodsGpn: map["goodsGpn"] as? String ?? "",
        name: map["name"] as? String ?? "",
        price: flutterDoubleOrNil(map["price"]) ?? 0,
        priceShow: map["priceShow"] as? String ?? "",
        originalPrice: flutterOriginalPrice(map["originalPrice"]),
        originalPriceShow: map["originalPriceShow"] as? String ?? "",
        stock: (map["stock"] as? NSNumber)?.intValue ?? 0,
        pic: map["pic"] as? String ?? "",
        photos: map["photos"] as? [String] ?? [],
        brief: map["brief"] as? String ?? "",
        // add-product-description-core-flutter: reverse path for simulate* test hooks,
        // same missing-key-tolerant style as `brief`. Native `LBProduct.init` declares
        // `description` right after `brief` (before `soldOut`) — Swift labeled calls must
        // match declaration order.
        description: map["description"] as? String ?? "",
        soldOut: flutterIntFlag(map["soldOut"]),
        isHot: flutterIntFlag(map["isHot"]),
        isOutSoon: flutterIntFlag(map["isOutSoon"]),
        narrateStatus: (map["narrateStatus"] as? NSNumber)?.intValue ?? 0,
        // Goods conclusion fields (goods-conclusion-fields spec): bool-tolerant,
        // absent → native LBProduct's defaulted value (a9d13a7).
        canView: flutterBoolOr(map["canView"], true),
        canBuy: flutterBoolOr(map["canBuy"], true),
        isNarrating: flutterBoolOr(map["isNarrating"], false),
        needLabel: flutterBoolOr(map["needLabel"], false),
        label: map["label"] as? String ?? "",
        isAwait: flutterIntFlag(map["isAwait"]),
        isAwaitNotice: flutterIntFlag(map["isAwaitNotice"]),
        beginTime: (map["beginTime"] as? NSNumber)?.intValue,
        endTime: (map["endTime"] as? NSNumber)?.intValue,
        diversionUrl: map["diversionUrl"] as? String ?? "",
        specifications: (map["specifications"] as? [[String: Any]] ?? [])
            .compactMap { flutterLBSpecFromArgs($0) },
        specOptions: (map["specOptions"] as? [[String: Any]] ?? []).map { opt in
            LBSpecOption(name: opt["name"] as? String ?? "",
                         child: opt["child"] as? [String] ?? [])
        },
        // add-product-video-id-core-flutter: reverse path for simulate* test
        // hooks; missing key → nil (same "as? String" tolerant convention as
        // the other optional fields above).
        videoId: map["videoId"] as? String)
}

private func flutterLBWinnerFromArgs(_ map: [String: Any]) -> LBWinner? {
    guard let id = map["id"] as? String else { return nil }
    let awardMap = map["award"] as? [String: Any]
    let award = LBAward(
        type: awardMap?["type"] as? String ?? "",
        code: awardMap?["code"] as? String ?? "",
        name: awardMap?["name"] as? String ?? "")
    return LBWinner(id: id,
                    eventId: (map["eventId"] as? Int) ?? 0,
                    title: map["title"] as? String ?? "",
                    award: award)
}

private func flutterLBSpecFromArgs(_ map: [String: Any]) -> LBSpec? {
    guard let id = map["id"] as? String else { return nil }
    // product-bridge-data-core: full LBSpec field set from camelCase map.
    return LBSpec(
        id: id,
        name: map["name"] as? String ?? "",
        specificationNo: map["specificationNo"] as? String ?? "",
        price: flutterDoubleOrNil(map["price"]) ?? 0,
        priceShow: map["priceShow"] as? String ?? "",
        originalPrice: flutterOriginalPrice(map["originalPrice"]),
        originalPriceShow: map["originalPriceShow"] as? String ?? "",
        stock: (map["stock"] as? NSNumber)?.intValue ?? 0,
        photos: map["photos"] as? [String] ?? [])
}

private func flutterLBHotItemFromArgs(_ map: [String: Any]) -> LBHotItem? {
    guard let id = map["id"] as? String else { return nil }
    // Build via the core memberwise init (core LBHotItem is not Decodable).
    return LBHotItem(
        id: id,
        cover: map["cover"] as? String ?? "",
        title: map["title"] as? String ?? "",
        duration: map["duration"] as? String ?? "00:00"
    )
}

private func flutterLBVideoItemFromArgs(_ map: [String: Any]) -> LBVideoItem? {
    guard let id = map["id"] as? String else { return nil }
    // Build via the core memberwise init (core LBVideoItem is not Decodable).
    // Mirrors the Android bridge's `lbVideoItemFrom`: only id / type / title /
    // cover / liveStatus / urls come from the host map; the rest default.
    return LBVideoItem(
        id: id,
        type: (map["type"] as? Int) ?? 1,
        title: map["title"] as? String ?? "",
        sessionName: nil,
        cover: map["cover"] as? String ?? "",
        preview: "",
        duration: 0,
        publishAt: "2000-01-01 00:00:00",
        watchNum: 0,
        pvNum: 0,
        liveStatus: (map["liveStatus"] as? Int) ?? 1,
        pin: 0,
        showPvNum: 0,
        liveurl: map["liveurl"] as? String ?? "",
        playbackurl: map["playbackurl"] as? String ?? "",
        previewTime: "00:00",
        showStock: false,
        goods: LBFeaturedGood(name: "", pic: "", price: "0", originalPrice: "0", soldOut: 0, stock: 0, status: 1)
    )
}

/// Serialize an `LBVideoItem` into the camelCase Flutter wire map shared by the
/// `fetchLatestLive` and `fetchWidget` method-channel handlers (`videos[]` entries).
private func flutterSerializeVideoItem(_ item: LBVideoItem) -> [String: Any] {
    var map: [String: Any] = [
        "id": item.id,
        "type": item.type,
        "title": item.title,
        "cover": item.cover,
        "preview": item.preview,
        "duration": item.duration,
        "publishAt": item.publishAt,
        "watchNum": item.watchNum,
        "pvNum": item.pvNum,
        "liveStatus": item.liveStatus,
        "pin": item.pin,
        "showPvNum": item.showPvNum,
        "liveurl": item.liveurl,
        "playbackurl": item.playbackurl,
        "previewTime": item.previewTime,
        "showStock": item.showStock,
    ]
    if let sessionName = item.sessionName { map["sessionName"] = sessionName }
    return map
}

// MARK: - Widget view factory (expand-simulate-bridge-parity Tier 2)

final class LivebuyWidgetViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return LivebuyFlutterWidgetView(frame: frame, viewId: viewId, messenger: messenger, args: args)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

final class LivebuyFlutterWidgetView: NSObject, FlutterPlatformView {
    private let widget: LivebuyWidgetCore
    private let methodChannel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {
        let shopId = (args as? [String: Any])?["shopId"] as? String ?? ""
        // The Dart side passes only `shopId` (parity with Android). Mode is a
        // rendering concern of the headless widget core — default to carousel;
        // honour an optional `mode` arg if a host ever supplies one.
        let mode: WidgetMode = ((args as? [String: Any])?["mode"] as? String) == "grid" ? .grid : .carousel
        widget = LivebuyWidgetCore(shopId: shopId, mode: mode)
        methodChannel = FlutterMethodChannel(
            name: "tv.livebuy/widget_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()
        // NOTE: an `onWidgetResponse` reverse-call (forwarding widget_color /
        // widget_bgcolor to Dart) was hand-stubbed here against a
        // `LivebuyWidgetCore.onWidgetResponse` hook that exists on NO platform SDK — it
        // never compiled. Removed (flutter-bridge-build gate). To restore, add the hook
        // to the iOS/Android SDK first (core + 4-platform parity), then re-wire.
        methodChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return }
            let callArgs = call.arguments as? [String: Any]
            switch call.method {
            case "simulateCardTap":
                if let map = callArgs, let video = flutterLBVideoItemFromArgs(map) {
                    self.widget.simulateCardTap(video)
                }
                result(nil)
            case "simulateClose":
                self.widget.simulateClose()
                result(nil)
            case "simulateCardVisibilityChanged":
                if let map = callArgs?["video"] as? [String: Any],
                   let video = flutterLBVideoItemFromArgs(map),
                   let visible = callArgs?["visible"] as? Bool {
                    self.widget.simulateCardVisibilityChanged(video, visible: visible)
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { widget }
}

// MARK: - FloatingWidget view factory (expand-simulate-bridge-parity Tier 2)

final class LivebuyFloatingWidgetViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return LivebuyFlutterFloatingWidgetView(frame: frame, viewId: viewId, messenger: messenger, args: args)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

final class LivebuyFlutterFloatingWidgetView: NSObject, FlutterPlatformView {
    private let widget: FloatingWidget
    private let methodChannel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {
        let videoId = (args as? [String: Any])?["videoId"] as? String ?? ""
        widget = FloatingWidget(videoId: videoId)
        methodChannel = FlutterMethodChannel(
            name: "tv.livebuy/floating_widget_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()
        methodChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return }
            switch call.method {
            case "simulateClose":
                self.widget.simulateClose()
                result(nil)
            case "simulateTap":
                self.widget.simulateTap()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { widget }
}
