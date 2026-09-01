import 'package:flutter/services.dart';
import 'event_listener.dart';
import 'models.dart';
import 'sdk_config.dart';

const MethodChannel _channel = MethodChannel('tv.livebuy/sdk');

/// Livebuy SDK entry point.
///
/// Call [configure] once at App launch before any other call. After configure(),
/// install a single [LBEventListener] with [setListener] to receive every SDK
/// event (player events, cart requests, auth gates, etc).
class LivebuySDK {
  LivebuySDK._();

  static LBEventListener? _listener;
  static bool _handlerInstalled = false;

  // MARK: - Configure

  /// Initialize the SDK. Must be called once at App launch.
  ///
  /// Per `sdk-config/spec.md`, the native side awaits `/sdk/config` under a
  /// stale-while-revalidate policy. On HMAC failure the future throws a
  /// [PlatformException] with code `NOT_CONFIGURED`. All other transport
  /// failures emit `SDK_CONFIG_LOAD_FAILED` and resolve successfully with
  /// SDK fallback default.
  static Future<void> configure(LBConfigOptions options) async {
    await _channel.invokeMethod('configure', {
      'apiKey': options.apiKey,
      'secret': options.secret,
      'shopId': options.shopId,
      'lang': options.lang?.code,
      'displayName': options.user?.displayName,
      'avatarUrl': options.user?.avatarUrl,
      'externalUserId': options.user?.externalUserId,
      'autoPipOnIntercept': options.autoPipOnIntercept,
      'apiVersion': options.apiVersion,
      'configFetchTimeoutMs': options.configFetchTimeoutMs,
      'enableConversionAttribution': options.enableConversionAttribution,
      'enablePowerProfileAdaptation': options.enablePowerProfileAdaptation,
      'enableStatReporting': options.enableStatReporting,
      'environment': options.environment.wireName,
    });
  }

  // MARK: - Conversion attribution (opt-in, conversion-attribution-context)

  /// Capture a Meta-ad deep link so the native SDK can derive `fbc` (the
  /// ad-click id). Pass the launch / app-link URL; the SDK extracts `fbclid`,
  /// formats `fb.1.<ms>.<fbclid>` and persists it. No-op when conversion
  /// attribution is disabled or the URL carries no `fbclid` (an absent `fbclid`
  /// does NOT overwrite an existing `fbc`). The SDK does not intercept deep
  /// links — only the host receives them.
  static Future<void> captureAdClick(String url) {
    return _channel.invokeMethod('captureAdClick', {'url': url});
  }

  /// Feed an already-extracted `fbclid` directly (host parsed the deep link
  /// itself). Persists a formatted `fbc`. No-op when disabled or blank.
  static Future<void> setFbclid(String fbclid) {
    return _channel.invokeMethod('setFbclid', {'fbclid': fbclid});
  }

  /// Set (or clear, with `null`) the `referer` source-page string injected into
  /// requests. In-memory; update per page. No-op when disabled.
  static Future<void> setReferer(String? referer) {
    return _channel.invokeMethod('setReferer', {'referer': referer});
  }

  /// Erase attribution identifiers (`fbc` / `referer` / `fbp`) for a host
  /// privacy / erasure request. A still-enabled subsystem mints a fresh `fbp`
  /// on next need.
  static Future<void> clearAttributionContext() {
    return _channel.invokeMethod('clearAttributionContext');
  }

  // MARK: - Stat reporting (opt-in, sdk-stat-reporting / flutter-stat-reporting-core)

  /// Erase the persisted SDK-native `/stat` state (the `video_people` per-day
  /// dedupe set + in-memory retention) for a host privacy / erasure request,
  /// mirroring [clearAttributionContext]. The `/stat` subsystem lives entirely
  /// natively in the wrapped iOS/Android SDK; this is a thin forwarding call
  /// (native routes to iOS `Livebuy.clearStatContext()` / Android
  /// `LivebuySDK.clearStatContext()`). Dart holds no `/stat` state of its own.
  static Future<void> clearStatContext() {
    return _channel.invokeMethod('clearStatContext');
  }

  /// Read the current `fbc` (Option C: hosts running their own Facebook SDK can
  /// forward it). Resolves `null` when disabled or no ad click captured.
  static Future<String?> currentFbc() {
    return _channel.invokeMethod<String?>('currentFbc');
  }

  /// Read the current `fbp` (Option C). Mints one on first read when enabled.
  /// Resolves `null` when conversion attribution is disabled.
  static Future<String?> currentFbp() {
    return _channel.invokeMethod<String?>('currentFbp');
  }

  // MARK: - Power profile (power-profile-adaptation, Flutter parity 第 6 支)

  /// Read the current thermal power-profile tier (`power-profile-adaptation`).
  /// Late subscribers (e.g. reference-ui animation throttling) can pull the
  /// current tier here; the `POWER_PROFILE_CHANGED` event pushes changes.
  ///
  /// Resolves **non-null**: the native getter returns [LBPowerProfile.full]
  /// (wire `"full"`) when power-profile adaptation is disabled, the subsystem
  /// is dormant, or the platform lacks thermal APIs (Android API<29), and
  /// [LBPowerProfile.fromWireName] maps any null / unknown wire value to
  /// [LBPowerProfile.full] as well. The subsystem lives entirely natively;
  /// this is a thin forwarding query, mirroring [currentFbc].
  static Future<LBPowerProfile> currentPowerProfile() async {
    final wire = await _channel.invokeMethod<String>('currentPowerProfile');
    return LBPowerProfile.fromWireName(wire);
  }

  /// Read-only auth-state query (auth-bind-session-ergonomics). Resolves `true`
  /// when a login session token is present (anchored on the token set by [login]
  /// / [bindSession]), `false` otherwise. [clearUser] flips it back to `false`;
  /// [setUser] / [setGuestNickname] do NOT change it (naming yourself as a guest
  /// is not authenticating). Use this for host re-bridge or login-gate gating
  /// instead of mirroring a host-side flag. The native side always returns a
  /// non-null bool; `?? false` guards only a channel-null edge.
  static Future<bool> isLoggedIn() async {
    return (await _channel.invokeMethod<bool>('isLoggedIn')) ?? false;
  }

  // MARK: - sdk-config (add-sdk-config-transport, task 4.4)

  /// Read the current merchant-configured SDKConfig snapshot. Returns the
  /// in-memory value (cache hit / server response / fallback default).
  ///
  /// Throws [PlatformException] with code `NOT_CONFIGURED` if [configure]
  /// has not yet completed.
  ///
  /// Cache is owned by the native side — Dart receives a read-only snapshot.
  static Future<SDKConfig> getSdkConfig() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getSdkConfig');
    return SDKConfig.fromMap(raw ?? const {});
  }

  /// Force a fresh `/sdk/config` fetch.
  ///
  /// Per `sdk-config/spec.md`:
  /// - Success + value differs → emits `SDK_CONFIG_REFRESHED` (source: `'refresh'`).
  /// - Success + value same → no event.
  /// - Failure → emits `SDK_CONFIG_LOAD_FAILED` (source: `'refresh'`),
  ///   preserves prior value (no fallback downgrade).
  ///
  /// Concurrent calls de-dup with any in-flight cold-start background refresh.
  static Future<void> refreshConfig() async {
    await _channel.invokeMethod('refreshConfig');
  }

  // MARK: - Reverse-notification APIs (Task 5.9 / 5.12)

  /// Notify the SDK that the host App user has logged in or switched accounts.
  /// Triggers a 30 s auto-replay of any action blocked by `AUTH_REQUIRED`.
  /// Must be called after [configure].
  static Future<void> setUser(LBUser user) {
    return _channel.invokeMethod('setUser', user.toMap());
  }

  /// Notify the SDK that the host App user has logged out.
  /// Reverts to Guest identity and clears any pending `AUTH_REQUIRED` action.
  static Future<void> clearUser() {
    return _channel.invokeMethod('clearUser');
  }

  /// Set the GUEST's LIVE-comment display name. Unlike [setUser] this is NOT a
  /// login: identity stays Guest (no `AUTH_REQUIRED` replay, `isGuest` stays
  /// true), it only sets the nickname shown on the user's own LIVE comments.
  /// Use this — not [setUser] — when a guest picks a nickname (設名 ≠ 登入).
  static Future<void> setGuestNickname(String name) {
    return _channel.invokeMethod('setGuestNickname', {'name': name});
  }

  /// Switch the SDK display language at runtime. Overrides [LBConfigOptions.lang]
  /// and the API-returned `lang`. Unsupported values are ignored with a warning.
  static Future<void> setLanguage(LBLocaleCode lang) {
    return _channel.invokeMethod('setLanguage', {'lang': lang.code});
  }

  /// Report a completed order to attribute it to an SDK-assisted add-to-cart.
  /// Same [orderId] within 24 h is deduplicated. Empty [sdkTrackCodes] *and*
  /// empty [items] is treated as a `client_misuse` no-op.
  static Future<void> notifyCheckoutCompleted({
    required String orderId,
    required List<String> sdkTrackCodes,
    List<LBCheckoutItem>? items,
  }) {
    return _channel.invokeMethod('notifyCheckoutCompleted', {
      'orderId': orderId,
      'sdkTrackCodes': sdkTrackCodes,
      'items': items?.map((i) => i.toMap()).toList(),
    });
  }

  /// Force-upload all pending offline events immediately, bypassing the backoff
  /// schedule. Returns once flushing completes or 5 seconds have elapsed.
  /// Concurrent callers receive equivalent results — the underlying flush is
  /// shared between them.
  static Future<LBFlushResult> flushPendingEvents() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('flushPendingEvents');
    return LBFlushResult.fromMap(raw ?? const {});
  }

  // MARK: - fetchLatestLive

  /// Query whether a live broadcast is currently in progress for widget [id].
  ///
  /// [id] is required; [ty] is OPTIONAL and OMITTED by default — `fetchLatestLive(id)`
  /// sends no `ty` so the backend returns the current `live_status == 1` live. Pass
  /// [ty] only for specific other needs. Returns the live item when one exists, or
  /// `null` when `data.video` is null. Throws [PlatformException] with code
  /// `NOT_CONFIGURED` if [configure] has not yet completed.
  static Future<LBVideoItem?> fetchLatestLive(String id, {String? ty}) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'fetchLatestLive',
      {'id': id, if (ty != null) 'ty': ty},
    );
    if (raw == null) return null;
    return LBVideoItem.fromMap(raw);
  }

  // MARK: - fetchWidget (fetch-widget-content)

  /// Headless one-shot fetch of widget content (`POST /sdk/widget`, carousel /
  /// grid page) for the drop-in widget container — without instantiating the
  /// native widget view. Mirrors the [fetchLatestLive] one-shot precedent.
  ///
  /// [shopId] is required; [page] is the 1-based page number (default `1`).
  /// Resolves with the raw snake_case wire `Map`: `videos` (a list of camelCase
  /// `LBVideoItem` maps), `current_page` / `last_page` (Int), the web-embed
  /// colors `widget_color` (Int) and `widget_bgcolor` (String; ABSENT when the
  /// backend omits it), plus `product_card` (String; the carousel card's
  /// product-card display mode `below` / `inside` / `hidden`).
  ///
  /// `product_card` is ABSENT from the map when the backend did not send it (the
  /// linetv branch does not). The SDK deliberately does NOT substitute the backend
  /// default `"inside"` anywhere along the bridge — "backend did not send it" and
  /// "backend explicitly sent `inside`" are two different facts, so a host reading
  /// `map['product_card']` gets `null` for the former and `"inside"` for the latter.
  /// Applying a default is the UI layer's job (widget-product-card-bridge-flutter).
  ///
  /// Because Flutter's `DefaultWidgetContent.handleWidgetSnapshot`
  /// itself reads the snake_case wire, the returned map can be fed DIRECTLY to
  /// `DefaultWidgetTemplate.handleWidgetSnapshot` (no intermediate decode — unlike
  /// RN's `decodeWidgetSnapshot`). Raw passthrough — the SDK does NOT interpret the
  /// colors. Throws [PlatformException] (`NOT_CONFIGURED`) before [configure].
  static Future<Map<String, Object?>> fetchWidget(String shopId, {int page = 1}) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'fetchWidget',
      {'id': shopId, 'page': page},
    );
    return raw == null ? <String, Object?>{} : Map<String, Object?>.from(raw);
  }

  // MARK: - login (login-session-token-core)

  /// Log in a member to obtain a login session token (login-session-token-core).
  ///
  /// [memberId] is required; [memberName] optional. No token is sent on the
  /// request; the resulting session token is stored natively (Dart never sees
  /// the raw token). Throws a [PlatformException] (native `LB_ERROR`) on a
  /// login failure (inner `code != 200`). [clearUser] clears the token;
  /// [setUser] does NOT.
  static Future<void> login(String memberId, {String? memberName}) {
    return _channel.invokeMethod('login', {
      'memberId': memberId,
      'memberName': memberName,
    });
  }

  // MARK: - bindSession / isLoggedIn (auth-bind-session-ergonomics)

  /// One-line member login (auth-bind-session-ergonomics). The THIRD identity
  /// entry point alongside [login] + [setUser] — it logs in AND sets the member
  /// identity in a single call, so an authenticated member never lingers as
  /// `Guest_XXXX` in chat from a forgotten [setUser]. Identity is set ONLY when
  /// login succeeds; on failure it throws a [PlatformException] (native
  /// `LB_ERROR`) and leaves no identity (no half-bound state). When [memberName]
  /// is omitted the native side falls back to the guest display name (never a
  /// blank name). To switch accounts call [clearUser] first. [memberId] is
  /// required; [memberName] / [avatarUrl] optional. The session token is stored
  /// natively (Dart never sees the raw token); [clearUser] clears it, [setUser]
  /// does NOT.
  static Future<void> bindSession(String memberId,
      {String? memberName, String? avatarUrl}) {
    return _channel.invokeMethod('bindSession', {
      'memberId': memberId,
      'memberName': memberName,
      'avatarUrl': avatarUrl,
    });
  }

  /// Read-only companion to [isLoggedIn] (bind-session-transition-idempotent
  /// -flutter-core): the `externalUserId` currently bound via [login] /
  /// [bindSession], or `null` when unbound / after [clearUser]. `bindSession`'s
  /// idempotent-same-member / auto-switch-account transition semantics are
  /// owned entirely by the native side (iOS `Livebuy.bindSession` / Android
  /// `LivebuySDK.bindSession`) — this is a thin forwarding query, no logic here.
  static Future<String?> boundMemberId() {
    return _channel.invokeMethod<String?>('boundMemberId');
  }

  // MARK: - addToCart (cart-add-tier2-unify, 統一加購流程)

  /// Unified Tier 2 add-to-cart (cart-add-tier2-unify). The native SDK calls
  /// `POST /sdk/video/addcart` and, on success, dispatches `CART_ADD_REQUEST` as a
  /// notification (no reply) carrying `buy_no` / `track` / `sdk_track_code` /
  /// `video_id` so the host adds the item to its own cart and (best-effort) reports
  /// the cart token via [reportCartTrack]. Resolves with the result.
  ///
  /// Error mapping: a 30s 重複加購 dedupe-hit throws [LBErrorCartAddDeduplicated]
  /// (host treats it as「已加入購物車」). An empty-`buy_no` popup-login boundary throws
  /// [LBErrorServer] with `code == 401` (needs-login). Other numeric codes map to
  /// [LBErrorServer]; non-numeric PlatformExceptions are rethrown unchanged.
  static Future<LBCartResult> addToCart(LBAddToCartOptions options) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'addToCart',
        options.toMap(),
      );
      return LBCartResult.fromMap(raw ?? const {});
    } on PlatformException catch (e) {
      // cart-add-tier2-unify: a 30s 重複加購 dedupe-hit reports code
      // `cart_add_deduplicated` → typed [LBErrorCartAddDeduplicated] (host treats it
      // as「已加入購物車」). A core serverError reports code = String(innerCode) (e.g.
      // "401" for an empty buy_no) → [LBErrorServer] so the requester can branch
      // needs-login (401) vs a genuine failure. Non-numeric codes (LB_ERROR /
      // NOT_CONFIGURED) keep the raw PlatformException.
      if (e.code == 'cart_add_deduplicated') {
        throw const LBErrorCartAddDeduplicated();
      }
      final code = int.tryParse(e.code);
      if (code != null) {
        throw LBErrorServer(code, e.message ?? '');
      }
      rethrow;
    }
  }

  /// Report a cart token for a `track.mode == 'token'` platform (addcart-track ④,
  /// `POST /sdk/video/addcart/track`). Call BEFORE checkout when an
  /// [LBCartResult.track] (or CART_ADD_REQUEST `track`) carries `mode == 'token'`;
  /// `trackId` is the host's own cart token, `buyNo` the prior add-to-cart result's
  /// buy_no. Conditional token (logged in → injected; guest → omitted). Delegates to
  /// native `reportCartTrack` (no Dart-built HTTP).
  static Future<void> reportCartTrack(
    String shopId,
    String buyNo,
    String trackId,
  ) {
    return _channel.invokeMethod('reportCartTrack', {
      'shopId': shopId,
      'buyNo': buyNo,
      'trackId': trackId,
    });
  }

  // MARK: - goods tracking (goods-await-notice-endpoints-core)

  /// Toggle restock-arrival tracking for a product (goods-await-notice §5.2,
  /// `POST /sdk/goods/await`). Login-required; [enabled] `true` tracks, `false`
  /// cancels. On success the native side dispatches `AWAIT_GOODS_CHANGED`.
  /// Independent of [setNoticeGoods] (separate backend row — not mutually
  /// exclusive). Throws `serverError(401)` when not logged in.
  static Future<void> setAwaitGoods(String goodsGpn, bool enabled) {
    return _channel.invokeMethod('setAwaitGoods', {
      'goodsGpn': goodsGpn,
      'enabled': enabled,
    });
  }

  /// Toggle restock-notice for a product (goods-await-notice §5.2,
  /// `POST /sdk/goods/notice`). Same wire/login contract as [setAwaitGoods];
  /// on success dispatches `NOTICE_GOODS_CHANGED`. Independent of [setAwaitGoods].
  static Future<void> setNoticeGoods(String goodsGpn, bool enabled) {
    return _channel.invokeMethod('setNoticeGoods', {
      'goodsGpn': goodsGpn,
      'enabled': enabled,
    });
  }

  // MARK: - setListener (Task 5.3)

  /// Install a single listener for every SDK event.
  ///
  /// Calling [setListener] a second time replaces the prior listener
  /// (matches iOS / Android native behaviour).
  static void setListener(LBEventListener? handler) {
    _listener = handler;
    if (!_handlerInstalled) {
      _channel.setMethodCallHandler(_onMethodCall);
      _handlerInstalled = true;
    }
    // Tell native to start dispatching (or stop).
    _channel.invokeMethod(handler != null ? 'registerListener' : 'unregisterListener');
  }

  // MARK: - Internal — native → Dart event dispatch

  static Future<Object?> _onMethodCall(MethodCall call) async {
    if (call.method != 'onSdkEvent') return null;
    final handler = _listener;
    if (handler == null) return LBEventReply.passthrough.toMap();

    final args = (call.arguments as Map?)?.cast<Object?, Object?>();
    if (args == null) return LBEventReply.passthrough.toMap();

    final eventName = args['eventName'] as String? ?? '';
    final params = ((args['params'] as Map?) ?? const {}).cast<String, Object?>();
    final shareMap = (args['shareContext'] as Map?)?.cast<Object?, Object?>();
    final share = shareMap == null
        ? null
        : LBShareContext(
            shareUrl: shareMap['defaultUrl'] as String? ?? '',
            title: shareMap['defaultTitle'] as String? ?? '',
          );

    try {
      final reply = await handler(LBSdkEvent(
        eventName: eventName, params: params, shareContext: share,
      ));
      final out = Map<String, Object?>.from(reply.toMap());
      // Round-trip share overrides back to native.
      if (share != null) {
        out['shareUrl'] = share.shareUrl;
        out['shareTitle'] = share.title;
      }
      return out;
    } catch (_) {
      // Listener exceptions are sandboxed: report passthrough so the SDK falls back to default UI.
      return LBEventReply.passthrough.toMap();
    }
  }
}
