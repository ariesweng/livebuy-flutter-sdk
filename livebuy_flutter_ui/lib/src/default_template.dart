import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config_merger.dart';
import 'default_active_event.dart';
import 'default_activity_feed.dart';
import 'default_auth_gate.dart';
import 'default_error_state.dart';
import 'default_goods_tracking.dart';
import 'default_identity_label.dart';
import 'default_info_tab.dart';
import 'default_moment_state.dart';
import 'default_notice_tab.dart';
import 'default_operation_rail.dart';
import 'default_product_sheet.dart';
import 'default_widget_content.dart';
import 'default_win_claim.dart';
import 'lb_ui_options.dart';

/// Marker class identifying the built-in Default template.
class DefaultTemplate {}

/// Event-join requester (livebuy-ui-event-join-and-error-state-template).
/// Injectable so the host wires the player ref's `requestEventJoin` (core emits
/// `eventJoinIntent`). The template calls this on a host-triggered「加入活動」
/// intent. When omitted, `joinEvent` still marks the item optimistically but
/// performs no core call (inert — headless).
typedef EventJoinRequester = void Function(int eid, String keyword);

/// Widget video-tap requester (fix-flutter-widget-template-handle-video-tap).
/// Injectable so the host wires navigation to a full-screen Player when a widget
/// card is tapped (RN/Flutter UI templates cannot present the native player
/// themselves — the native player is owned by the core bridge). The template
/// calls this with the tapped card's `videoId`. When omitted, `handleVideoTap`
/// is an inert no-op (headless-safe; does not change install/attach flow).
/// Mirrors RN `onVideoTap?(videoId)`; iOS/Android templates hold + present the
/// native player directly with a full `LBVideoItem`.
typedef WidgetVideoTapRequester = void Function(String videoId);

/// Guest rename-intent requester (auth-gate-template-state). Injectable so the
/// host wires the closure that calls its `LivebuyPlayerController.operationPanel
/// .simulateGuestNameEditTap()` (the core exit emitting `GUEST_NAME_EDIT_REQUEST`
/// — passthrough, non-navigation, no auto-PiP). On Flutter the core
/// `LivebuyPlayerController` exposes NO `guestNameEditRequest()` symbol the
/// template could hold (no native Player ref in Dart), so the「請求改名」forward
/// is this injectable typedef — EXACT parity with [EventJoinRequester] / RN's
/// `requestEventJoin` forward. Default `(){}` is an inert no-op (headless-safe);
/// the template draws NO rename UI and changes NO event semantics.
typedef GuestNameEditRequester = void Function();

/// View-cart requester (view-cart-event-flutter-template). The「查看購物車」CTA
/// forward — injectable so the host wires the player ref's
/// `requestViewCart(productId:)` (core emits `VIEW_CART`, notification /
/// non-navigation / no auto-PiP). `productId` is the current product detail's id
/// (商品詳情頁 CTA) or `null` (商品列表底部 CTA, so the core seam omits the
/// `product_id` key). EXACT parity with [GuestNameEditRequester] /
/// [EventJoinRequester]. Default `(_) {}` is an inert no-op (headless-safe); the
/// template owns NO cart / checkout UI and changes NO event semantics.
typedef ViewCartRequester = void Function(String? productId);

/// Video-load requester (swipe-navigate-flutter-template). Injectable so the host
/// wires the player ref's `load(videoId)` (the Flutter template holds NO native
/// player ref — `LBChannel` is not bridged to Dart). The template's
/// `navigateToPrev()` / `navigateToNext()` forwarders call this with the resolved
/// adjacent-video id so a vertical swipe can switch videos. When omitted, the
/// default `(_) {}` is an inert no-op (headless-safe) — EXACT parity with
/// [EventJoinRequester] / [GuestNameEditRequester] / `AddToCartRequester`.
typedef VideoLoadRequester = void Function(String videoId);

/// Mute-intent forwarder (flutter-player-toggle-mute-template). Injectable so the
/// reference-ui / host wires the core `LivebuyPlayerController.setMuted` (which
/// routes to the active engine — IVS / AVPlayer) and unit tests assert the
/// forward with a `Capturing` fake. The Flutter template holds NO native player
/// ref (`LBChannel` is not bridged to Dart), so [DefaultPlayerTemplate.setMuted]
/// delegates the mute intent to this setter — EXACT parity with
/// [VideoLoadRequester] / Android `MutedSetter`. Default `(_) {}` is an inert
/// no-op (headless-safe / unit tests / no wiring → no core call; the presentation
/// half via [DefaultPlayerTemplate.handleMuted] still updates). The ACTUAL wiring
/// (`(muted) => controller.setMuted(muted)`) is injected by the downstream
/// `flutter-reference-ui` container, not this template layer.
typedef MutedSetter = void Function(bool muted);

/// Play/pause-toggle forwarder (flutter-vod-playback-progress-template, VOD-2
/// control exit). Injectable so the `flutter-reference-ui` container wires the
/// core `LivebuyPlayerController.togglePlayPause()` — EXACT parity with
/// [MutedSetter]: the Flutter template holds no native player ref, so
/// [DefaultPlayerTemplate.togglePlayPause] delegates to this closure. Default
/// `(){}` is an inert no-op (headless-safe).
typedef TogglePlayPauseRequester = void Function();

/// VOD seek forwarder (flutter-vod-playback-progress-template, VOD-2 control
/// exit). Shared shape for BOTH [DefaultPlayerTemplate.seek] and
/// [DefaultPlayerTemplate.seekBy] (injected as two SEPARATE closures — one per
/// method — since a real wiring routes them to two different core methods,
/// `LivebuyPlayerController.seek` / `.seekBy`). `liveStatus` / `duration` are
/// verbatim pass-through to the injected closure — the template does NOT
/// derive them from its own [DefaultPlayerHeaderState.isLive] /
/// [DefaultPlaybackProgressState.duration]; the caller supplies them to opt
/// into the core's `vodScrubAllowed` gate, mirroring the core's own optional-
/// gate contract. EXACT parity with [MutedSetter]: default no-op is inert
/// (headless-safe); the `flutter-reference-ui` container injects the real
/// `(seconds, {liveStatus, duration}) => controller.seek(...)` /
/// `.seekBy(...)` closures.
typedef VodSeekRequester = void Function(double seconds,
    {int? liveStatus, double? duration});

/// In-app browser opener (Task 2.3 / 2.5). Injectable so unit tests can verify
/// the diversion path with a fake opener instead of launching a real browser.
///
/// url-open-host-routing-template-flutter: this is the `LBURLOpenTarget.inApp`
/// -branch-only seam. [_openResolvedUrl] is the only caller; it always passes
/// [LBURLOpenDecision.url]`.toString()` (never the raw `diversionUrl` string).
/// See [ExternalUrlOpener] for the sibling seam that handles the other branch.
typedef InAppBrowserOpener = Future<void> Function(String url);

/// External URL opener (url-open-host-routing-template-flutter). Injectable so
/// unit tests can verify the diversion path with a fake opener instead of
/// launching a real browser / OS chooser.
///
/// This is the `LBURLOpenTarget.external`-branch-only seam — the URL is handed
/// to the SYSTEM URL router (`LaunchMode.externalApplication`); the user may
/// leave the app. MUST NOT be loaded into any WebView / in-app browser view.
/// Deliberately a SEPARATE typedef from [InAppBrowserOpener] (not one seam plus
/// a `target` parameter) so an injector cannot silently forget to branch on
/// `target` — misrouting requires writing the wrong thing, not merely omitting
/// a check.
typedef ExternalUrlOpener = Future<void> Function(String url);

/// Default opener: launches the purchase page in an in-app browser view
/// (`LaunchMode.inAppBrowserView`) so the user stays in-app, the live keeps
/// playing, and they can return. Malformed URL → safe no-op.
Future<void> _defaultInAppBrowserOpener(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
}

/// Default opener: hands the URL to the SYSTEM URL router
/// (`LaunchMode.externalApplication`, url-open-host-routing-template-flutter)
/// — the user may leave the app. Malformed URL → safe no-op. Mirrors
/// [_defaultInAppBrowserOpener]; the only difference is the [LaunchMode].
Future<void> _defaultExternalUrlOpener(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The layout keys each Default template understands (Task 3.1 / D7). Keys the
/// backend (`sdkConfig.layout`) sends that are not in these sets are silently
/// ignored (no crash, other keys unaffected) but surfaced via a debug log.
class DefaultLayoutKeys {
  static const Set<String> player = {'productOverlay_position', 'productOverlay_style'};
  static const Set<String> widget = {'carousel_effect', 'carousel_autoPlay', 'grid_columns'};

  static void logUnknown(String scope, Map<String, Object?>? incoming) {
    if (incoming == null) return;
    final known = scope == 'widget' ? widget : player;
    for (final key in incoming.keys) {
      if (!known.contains(key)) {
        assert(() {
          debugPrint('[DefaultTemplate] unrecognized $scope layout key: $key');
          return true;
        }());
      }
    }
  }
}

/// Effective config snapshot for a single Player / Widget instance.
/// Reads config once at instantiate time (D6 — not reactive).
class EffectiveConfig {
  final SDKConfig _sdkConfig;
  final LBUIOptions? _hostOptions;

  const EffectiveConfig(this._sdkConfig, this._hostOptions);

  // templateDefaults always contains `key`, so the merge never returns null for
  // a well-known key — the old `result == null` log was dead code (D7). Unknown-key
  // detection now happens once at instantiate time via DefaultLayoutKeys.logUnknown().
  Object? layoutValue(String key, Object defaultValue) {
    final result = ConfigMerger.effectiveLayoutValue(
      key: key,
      sdkMap: _sdkConfig.layout?.player,
      hostMap: _hostOptions?.layoutPlayer,
      templateDefaults: {key: defaultValue},
    );
    return result ?? defaultValue;
  }

  Object? widgetLayoutValue(String key, Object defaultValue) {
    final result = ConfigMerger.effectiveLayoutValue(
      key: key,
      sdkMap: _sdkConfig.layout?.widget,
      hostMap: _hostOptions?.layoutWidget,
      templateDefaults: {key: defaultValue},
    );
    return result ?? defaultValue;
  }
}

/// 置頂留言（chat-message-taxonomy ⑤，messages `data.top`，parity iOS `LBPinnedMessage` / RN
/// `PinnedMessage`）。`kind` 為 wire 字串（僅 `comment`（`name` 非空）或 `host`（`name` 空），上游
/// 無法細分）。reference-ui 讀 [DefaultPlayerTemplate.pinned] 渲染置頂橫幅。
class PinnedMessage {
  final String kind;
  final String text;
  final String name;
  final int id;
  const PinnedMessage({
    required this.kind,
    required this.text,
    required this.name,
    required this.id,
  });

  /// Decode a unified POLL_RECEIVED `top` (`{kind, text, name, id}`) → [PinnedMessage] | null.
  /// 無有效置頂文字（text 空）→ null（視為無釘選）。
  static PinnedMessage? fromTop(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String || text.isEmpty) return null;
    return PinnedMessage(
      kind: raw['kind'] is String ? raw['kind'] as String : 'comment',
      text: text,
      name: raw['name'] is String ? raw['name'] as String : '',
      id: (raw['id'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PinnedMessage &&
      other.kind == kind &&
      other.text == text &&
      other.name == name &&
      other.id == id;

  @override
  int get hashCode => Object.hash(kind, text, name, id);
}

/// Pure classifier (parity iOS/Android/RN `isAddToCartAuthRequired`): `true` only for the core
///「needs login」signal — [LBErrorServer] with `code == 401` (raised for an empty `buy_no`).
/// `false` for every other error (other server codes / network / generic exceptions). Extracted
/// so the route-B catch's branching is unit-testable in isolation.
bool isAddToCartAuthRequired(Object error) =>
    error is LBErrorServer && error.code == 401;

/// Pure classifier (cart-add-tier2-unify, parity iOS/Android/RN `LBError.cartAddDeduplicated`):
/// `true` only for the core 30s 重複加購 dedupe-hit — [LBErrorCartAddDeduplicated]. `false` for
/// every other error. Extracted so the route-B catch's branching is unit-testable in isolation.
bool isAddToCartDeduplicated(Object error) => error is LBErrorCartAddDeduplicated;

/// Default Player template event handler (Task 6.5, 6.7).
///
/// `DISMISS_REQUEST` → `Navigator.pop(context)`
class DefaultPlayerTemplate {
  final SDKConfig sdkConfig;
  final LBUIOptions? hostOptions;
  final InAppBrowserOpener _openInAppBrowser;

  /// url-open-host-routing-template-flutter — the `external`-branch seam for
  /// [_openResolvedUrl]. See [ExternalUrlOpener] doc for the seam's contract.
  final ExternalUrlOpener _openExternalUrl;

  /// §1 — merged activity + chat feed view-model (host binds [DefaultActivityFeed.items]).
  final DefaultActivityFeed feed;

  /// §2 / §3 / §4 — win unclaimed entry + claim submit + result-state view-model.
  final DefaultWinClaim winClaim;

  /// live-activity-entry-flutter-template — merged「進行中活動」view-model
  /// (`activeEvents()` snapshot + `ACTIVE_EVENT_STARTED` fire-once push). Host
  /// binds [DefaultActiveEvent.current] / [DefaultActiveEvent.hasActiveEvent]
  /// to draw the `LBWinEntry(variant="activity")` entry + `LBActivitySheet`,
  /// and calls [DefaultActiveEvent.join] for the「立即參加」CTA (reuses the
  /// SAME [EventJoinRequester] seam as [joinEvent] — design.md D3).
  final DefaultActiveEvent activeEvent;

  /// Player error-state view-model (livebuy-ui-event-join-and-error-state-template).
  /// Host binds [DefaultErrorState.current] for `LBPErrorScreen`. The host wires
  /// its `LivebuyPlayer.onError` → [handleError]; clearing is auto-driven from
  /// the unified `VIDEO_STATE_CHANGE` via [handlePlayerStateChange].
  final DefaultErrorState errorState = DefaultErrorState();

  // expose-player-moment-state-template — five host-bindable moment view-models
  // (each its own ChangeNotifier; host binds with `ListenableBuilder`). All are
  // host-wired via the `handle*` methods below (momentState is NOT bridged to
  // Flutter — D8); only StartScreen phase is auto-wired from VIDEO_STATE_CHANGE
  // (see [handlePlayerStateChange]). READ surface public; ingestion `@internal`.

  /// StartScreen phase view-model — host draws / dismisses the opening splash.
  final DefaultStartScreenState startScreen = DefaultStartScreenState();

  /// Upcoming (直播預告 awaiting-live) view-model — host / reference-ui draw the
  /// upcoming LIVE chrome (countdown background `cover` + `scheduledStartAt`) +
  /// the opening-MP4 (`introPlaying`) gate. Parity iOS / Android `DefaultUpcomingState`.
  /// HOST-FED via [handleUpcoming] (the Flutter core forwards only the upcoming
  /// channel fields as `LBPlayerChannelInfo` — `upcoming-intro-core-flutter`).
  final DefaultUpcomingState upcoming = DefaultUpcomingState();

  /// EndScreen view-model — `next` / `hot` + optional auto-next countdown.
  final DefaultEndScreenState endScreen = DefaultEndScreenState();

  /// ProductOverlay view-model — products snapshot + in-narration active product.
  final DefaultProductOverlayState productOverlay = DefaultProductOverlayState();

  /// PlayerHeader view-model — isSubscribed / viewerCount / muted.
  final DefaultPlayerHeaderState header = DefaultPlayerHeaderState();

  /// SubtitleTrack view-model — available / enabled.
  final DefaultSubtitleState subtitle = DefaultSubtitleState();

  /// VOD playback-progress view-model (VOD-2) — position / duration / isPlaying /
  /// isReplay. Host-fed (the host echoes the native progress). `isReplay` drives
  /// the reference-ui LIVE bottom bar's "聊天室已關閉" replay variant.
  final DefaultPlaybackProgressState playbackProgress =
      DefaultPlaybackProgressState();

  /// VOD「正在介紹中的商品」清單（rb-flutter-now-introducing parity，問題 9/10）：所有
  /// `[beginTime, endTime)` 涵蓋 `playbackProgress.position` 的商品，依 `beginTime` **升冪**。純
  /// computed——讀既有 `productOverlay.products` + `playbackProgress.position`，無第二份狀態。
  /// reference-ui 的 VOD 介紹中卡輪播（真實圖 + 滿寬 + 多商品輪播）讀此清單。
  ///
  /// 註：與既有 singular `productOverlay.activeProduct`（← core narratingProduct）為不同來源——
  /// 後者是 core「講解中」單一商品，本清單是 playhead vs beginTime/endTime 推導的複數。
  List<LBProduct> get vodActiveProducts {
    final pos = playbackProgress.position;
    final hits = productOverlay.products.where((p) {
      final b = p.beginTime;
      final e = p.endTime;
      return b != null && e != null && b.toDouble() <= pos && pos < e.toDouble();
    }).toList();
    hits.sort((a, b) => (a.beginTime ?? 0).compareTo(b.beginTime ?? 0));
    return hits;
  }

  /// LIVE「正在介紹中」商品清單（rb-flutter-live-now-introducing parity，問題 7）：所有
  /// `narrate_status == 2` 的商品，依資料層 `productOverlay.products` 順序（**不 re-sort**）。後端 LIVE
  /// **可同時多件** `narrate_status == 2`（live-multi-narrating-product-contract）。純 computed——讀既有
  /// `productOverlay.products`，無第二份狀態，不改既有 singular `productOverlay.activeProduct`（← core
  /// narratingProduct 取第一件）/ pinned 卡路徑。reference-ui LIVE 介紹中卡輪播（多商品 + 分頁點）讀此清單。
  /// 對等 VOD 的 [vodActiveProducts]。Mirrors iOS / Android / RN `liveActiveProducts`.
  List<LBProduct> get liveActiveProducts =>
      productOverlay.products.where((p) => p.narrateStatus == 2).toList();

  /// swipe-navigate-flutter-template — read-only prev/next adjacent-video nav
  /// targets view-model (its own ChangeNotifier; host binds with
  /// `ListenableBuilder`). Host-fed via [handleNavTargets] (the Flutter core does
  /// NOT bridge `LBChannel` to Dart). Drives the reference-ui vertical-swipe
  /// switch-video gesture via [navigateToPrev] / [navigateToNext].
  final DefaultPlayerNavigation navigation = DefaultPlayerNavigation();

  // auth-gate-template-state — two host-bindable auth view-models (each its own
  // ChangeNotifier; host binds with `ListenableBuilder`, fan-in is automatic).
  // Driven by the unified bridge listener (route B): `AUTH_REQUIRED` →
  // [handleAuthRequired], `AUTH_STATE_CHANGED` → [handleAuthStateChanged].

  /// Auth-gate「請先登入」view-model — host binds [DefaultAuthGate.current]. A host
  /// that installs its own primary `AUTH_REQUIRED` handling sets
  /// `authGate.hostOwnsAuthGate = true` to exclude the template's auth-gate state.
  final DefaultAuthGate authGate = DefaultAuthGate();

  /// Identity-label view-model — host binds [DefaultIdentityLabel.current] for
  /// `PlayerHeader` / `ChatView`. null until the first `AUTH_STATE_CHANGED`
  /// (NOT seeded from configure identity — single source = `AUTH_STATE_CHANGED`).
  final DefaultIdentityLabel identityLabel = DefaultIdentityLabel();

  // await-toggle-and-notice-tab-template-state — goods-tracking dual switch +
  // notice-tab open-state (each its own ChangeNotifier; host binds with
  // `ListenableBuilder`). Driven by the unified bridge listener for the
  // authoritative `AWAIT/NOTICE_GOODS_CHANGED` broadcasts; seed + notice text are
  // host-fed (Flutter `LBProduct` has no isAwait flags and no channel ref here).

  /// Per-product 到貨追蹤 / 補貨通知 dual switch — host binds and reads
  /// [DefaultGoodsTracking.awaitEnabled] / [DefaultGoodsTracking.noticeEnabled].
  final DefaultGoodsTracking goodsTracking;

  /// VideoInfoPanel 公告分頁 open-state — host binds [DefaultNoticeTab.current].
  final DefaultNoticeTab noticeTab = DefaultNoticeTab();

  // player-chrome-template — two host-bindable player-chrome view-models (each its
  // own ChangeNotifier; host binds with `ListenableBuilder`, fan-in is automatic).
  // The PlayerHeader top-bar chrome補欄 lives ON the existing [header] view-model
  // (D3 — pure添欄, no new model). All host-fed via the `handle*` methods below
  // (channel / momentState are NOT bridged to Flutter — D6), like moment-state.

  /// OperationPanel side-rail view-model — ordered `{ kind, enabled }` items +
  /// bag-count + heart-burst tick + muted. Host binds and reads
  /// [DefaultOperationRail.items] / .bagCount / .heartBurstTick / .muted.
  final DefaultOperationRail operationRail = DefaultOperationRail();

  /// VideoInfoPanel info-tab + two-tab-switch view-model. `isSubscribed` reads the
  /// SAME truth as [header] (single-source, D4); the `notice` tab is gated on
  /// [noticeTab].canOpen (auto-falls-back to `info` when 公告轉空). Host binds
  /// [DefaultInfoTab.fields] / .activeTab / .isSubscribed.
  late final DefaultInfoTab infoTab =
      DefaultInfoTab(header: header, noticeTab: noticeTab);

  // product-sheet-stack-template — five host-bindable 商品 sheet-stack view-models
  // (each its own ChangeNotifier; host binds with `ListenableBuilder`, fan-in is
  // automatic). Driven by [handleProductTap] (diversion==0) + the route-B
  // [addToCart] intent (delegates the injected [_addToCartRequester]). The
  // DATA comes from the bridge `LBProduct` (price / photos / stock /
  // specifications / specOptions — supplied by product-bridge-data-core).

  /// product-detail sheet view-model — host binds [DefaultProductSheet.detail]
  /// for `LBPBottomSheet` + `LBPProductRow`. Set on a `diversion==0` productTap.
  final DefaultProductSheet productSheet = DefaultProductSheet();

  /// variant-picker view-model — host binds [DefaultVariantPicker.groups] /
  /// .selection / .selectedSpec for `LBPVariantPicker`.
  final DefaultVariantPicker variantPicker = DefaultVariantPicker();

  /// qty-stepper view-model — host binds [DefaultQtyStepper.state] for
  /// `LBPQtyStepper`.
  final DefaultQtyStepper qtyStepper = DefaultQtyStepper();

  /// mini-cart peek view-model — host binds [DefaultMiniCart.peek] for
  /// `LBPMiniCart`.
  final DefaultMiniCart miniCart = DefaultMiniCart();

  /// cart-CTA view-model — host binds [DefaultCartCTA.count] for `LBPCartCTA`.
  final DefaultCartCTA cartCTA = DefaultCartCTA();

  /// Set by the host when it installs its own primary `productTap` / 加購 handling
  /// and takes over add-to-cart via route A (`CART_ADD_REQUEST`). While true the
  /// template does NOT set product-detail state on productTap AND does NOT
  /// delegate route-B `addToCart` (avoids double-write with route A). Parity
  /// with `DefaultAuthGate.hostOwnsAuthGate` / `DefaultActivityFeed.hostOwnsActivity`.
  bool hostOwnsCart = false;

  /// Last route-B add-to-cart failure flag — host binds to show「加購失敗」(D5).
  /// Reset to false at the start of each [addToCart] attempt; set true on a
  /// throwing delegate. Exposed via [addToCartFailed].
  bool _addToCartFailed = false;

  /// True when the most recent [addToCart] attempt failed (host shows a toast).
  bool get addToCartFailed => _addToCartFailed;

  /// Last route-B add-to-cart「需登入」flag, orthogonal to [_addToCartFailed]. Set true when
  /// the route-B add threw the core「needs login」signal ([LBErrorServer] code 401, raised for an
  /// empty `buy_no`) so the reference-ui shows the login gate instead of the failure banner.
  /// Reset alongside the failure flag (new attempt / sheet open). parity iOS/Android/RN.
  bool _addToCartNeedsLogin = false;

  /// True when the most recent [addToCart] rejected with the「需登入」signal (serverError 401).
  /// Orthogonal to [addToCartFailed] — the reference-ui shows the login gate, not the banner.
  bool get addToCartNeedsLogin => _addToCartNeedsLogin;

  /// True when [addToCart] was blocked because the product has specs but the
  /// selection is not complete (host shows「請選規格」, D5). Reset at each attempt.
  bool _needsVariantSelection = false;

  /// True when the last [addToCart] was gated by an incomplete variant selection.
  bool get needsVariantSelection => _needsVariantSelection;

  /// 加購「請求中」flag（cart-add-loading-state-flutter, parity iOS/Android/RN `addToCartInFlight`）。
  /// [addToCart] 通過全部 guards 後、委派 [addToCartRequester] 前同步設 true（在第一個 `await` 之前，
  /// 使 reference-ui `final f = addToCart()` 回來時可立即讀），各結果（success / dedupe / needs-login /
  /// failure）皆設回 false；開新詳情（[_openProductDetail]）reset。與 [addToCartFailed] /
  /// [addToCartNeedsLogin] / [needsVariantSelection] 正交。**純欄位、無 notify**（template 非
  /// ChangeNotifier；reference-ui 以同步前綴讀 + await 後 setState 呈現，與既有 transient 旗標同模式）。
  bool _addToCartInFlight = false;

  /// True 當一次 [addToCart] 請求正在飛（已通過 guards、尚未回結果）。reference-ui 據此鎖加購 CTA /
  /// 顯示 spinner（spinner +「加入中…」、鎖 stepper/規格）。預設 false。
  bool get addToCartInFlight => _addToCartInFlight;

  /// 會員等級限定旗標（restriction-gate ②），由統一 `VIDEO_OPEN` 事件的 `is_restriction`
  /// 衍生（`== 1` → true）供 reference-ui 疊升級遮罩。**軟性顯示閘門**：core 不擋播放。
  /// Flutter 無 `ingestChannel()`，故由 [TemplateAttachment] 路由 `VIDEO_OPEN` 呼叫
  /// [applyRestriction]（iOS / Android 由 `ingestChannel` 衍生）。預設 false。其自有
  /// `ChangeNotifier`（reference-ui 併入 `Listenable.merge`），內建 diff-then-notify。
  final ValueNotifier<bool> restriction = ValueNotifier<bool>(false);

  /// 置頂留言（chat-message-taxonomy ⑤），由 [handlePinned] 從 `poll.top` 設定，供 reference-ui
  /// 渲染置頂橫幅。冪等：每輪以當前釘選狀態覆蓋，取消釘選 → null。其自有 `ValueNotifier`
  /// （reference-ui 併入 `Listenable.merge`），內建 diff-then-notify（值相等 `==` 不重發）。
  final ValueNotifier<PinnedMessage?> pinned = ValueNotifier<PinnedMessage?>(null);

  /// 置頂留言 view-model（chat-message-taxonomy ⑤，來自 `poll.top`）。無釘選 → null。
  PinnedMessage? get pinnedMessage => pinned.value;

  /// 由統一 `POLL_RECEIVED` 的 `top` 設定置頂（`{kind, text, name, id}`；text 空 / 缺 → null）。
  /// `ValueNotifier` 內建 diff-then-notify。由 [TemplateAttachment] 的 push 路由後呼叫。
  void handlePinned(Object? top) => pinned.value = PinnedMessage.fromTop(top);

  /// 會員等級限定 view-model（restriction-gate ②）。reference-ui 讀此值在 `isRestricted`
  /// 時疊升級遮罩；core 不擋播放（軟性顯示閘門）。預設 false。
  bool get isRestricted => restriction.value;

  /// 由統一 `VIDEO_OPEN` 事件的 `is_restriction` 衍生 `isRestricted`（`== 1` → true，
  /// 非 1 / 缺欄 → false fail-open）。`ValueNotifier` 內建 diff-then-notify（相同值不重發），
  /// 對齊 iOS `ingestChannel` 的 coalescing 語意。由 [TemplateAttachment] 的 `VIDEO_OPEN`
  /// case 呼叫（Flutter 無 ingestChannel）。
  void applyRestriction(bool restricted) => restriction.value = restricted;

  /// 當前影片短碼（cart-add-tier2-unify），由統一 `VIDEO_OPEN` 事件（`params.video_id`）追蹤，
  /// 串接進 [addToCart] → `LBAddToCartOptions.videoId`，使 core 的 `CART_ADD_REQUEST` 帶正確
  /// `video_id`。Flutter 無 `ingestChannel()`，故由 [TemplateAttachment] VIDEO_OPEN 呼叫
  /// [setCurrentVideoId]。null until first VIDEO_OPEN（事件 `video_id` 退化為 `""`，不阻擋加購）。
  String? _currentVideoId;

  /// 當前影片短碼（cart-add-tier2-unify）。供測試 / host 檢視。
  String? get currentVideoId => _currentVideoId;

  /// 由統一 `VIDEO_OPEN` 事件的 `video_id` 追蹤當前影片短碼（cart-add-tier2-unify）。
  /// pure assignment（無像素影響、不 notify）。空 / 非字串 → 不覆寫（fail-safe）。由
  /// [TemplateAttachment] 的 `VIDEO_OPEN` case 呼叫（Flutter 無 ingestChannel）。
  void setCurrentVideoId(String? videoId) {
    if (videoId != null && videoId.isNotEmpty) _currentVideoId = videoId;
  }

  /// 當前 channel 的「更多商品」候選清單(`LBChannel.otherGoods`,
  /// expose-other-goods-recommendations-template)。Flutter 無 `ingestChannel()`,
  /// 由 host 呼叫 [setOtherGoods] 餵入(parity `setCurrentVideoId` / `setShopId`)。
  /// [_openProductDetail] 開啟商品詳情時據此算出
  /// `LBProductDetailState.recommendations`(排除目前商品、不裁切張數)。未餵入 /
  /// headless 單元測試時為空清單。
  List<LBProduct> _currentOtherGoods = const [];

  /// Host-fed「更多商品」候選清單(`channel.otherGoods`)。pure assignment(無像素
  /// 影響、不 notify)——下次開啟商品詳情時才生效(parity `setCurrentVideoId`)。
  void setOtherGoods(List<LBProduct>? otherGoods) {
    _currentOtherGoods = otherGoods ?? const [];
  }

  final AddToCartRequester _addToCartRequester;

  /// The shop id used to build route-B `LBAddToCartOptions` (host-supplied — the
  /// Flutter bridge `LBProduct` has no shopId; the host knows it from its
  /// `channel`). Empty until [setShopId] is called; an empty shopId still builds
  /// the options (core injects auth) but the host should set it.
  String _shopId = '';

  // `channel.start` non-empty drives the StartScreen splash phase (D2). It is
  // NOT carried by VIDEO_STATE_CHANGE, so the host supplies it via
  // [handleStartUrl] / [handleUpcoming]; default false → no-splash path
  // (loading → done). Both sources are `channel.start` (one authoritative field).
  bool _hasStart = false;

  // upcoming-intro-template — the latest canonical player state, cached by
  // [handlePlayerStateChange] so [handleUpcoming] (the host calls it on channel load,
  // typically right after the state callback) can derive `upcoming` against it.
  // Parity with the Android template's cached `lastState`.
  String _lastState = 'loading';

  final EventJoinRequester _eventJoinRequester;

  final GuestNameEditRequester _guestNameEditRequester;

  /// view-cart-event-flutter-template — host-wired `requestViewCart(productId)`
  /// delegate for [openCart]. Default `(_) {}` is an inert no-op (headless-safe).
  final ViewCartRequester _viewCartRequester;

  /// swipe-navigate-flutter-template — host-wired `load(videoId)` delegate for the
  /// nav forwarders. Default `(_) {}` is an inert no-op (headless-safe).
  final VideoLoadRequester _videoLoadRequester;

  /// flutter-player-toggle-mute-template — reference-ui/host-wired mute-intent
  /// forwarder for [setMuted] / [toggleMute] (`(muted) =>
  /// controller.setMuted(muted)`). Default `(_) {}` is an inert no-op
  /// (headless-safe). Mirrors Android `setMutedRequester`.
  final MutedSetter _setMutedRequester;

  /// flutter-vod-playback-progress-template — reference-ui/host-wired
  /// play/pause forwarder for [togglePlayPause] (`() =>
  /// controller.togglePlayPause()`). Default `(){}` is an inert no-op
  /// (headless-safe).
  final TogglePlayPauseRequester _togglePlayPauseRequester;

  /// flutter-vod-playback-progress-template — reference-ui/host-wired absolute
  /// seek forwarder for [seek] (`(seconds, {liveStatus, duration}) =>
  /// controller.seek(seconds, liveStatus: liveStatus, duration: duration)`).
  /// Default is an inert no-op (headless-safe).
  final VodSeekRequester _seekRequester;

  /// flutter-vod-playback-progress-template — reference-ui/host-wired relative
  /// seek forwarder for [seekBy] (`(seconds, {liveStatus, duration}) =>
  /// controller.seekBy(seconds, liveStatus: liveStatus, duration: duration)`).
  /// A SEPARATE closure from [_seekRequester] (independent injection; same
  /// [VodSeekRequester] shape). Default is an inert no-op (headless-safe).
  final VodSeekRequester _seekByRequester;

  DefaultPlayerTemplate({
    required this.sdkConfig,
    this.hostOptions,
    InAppBrowserOpener? openInAppBrowser,
    // url-open-host-routing-template-flutter — the `external`-branch seam.
    // Optional named parameter; omitted → falls back to `_defaultExternalUrlOpener`
    // (`LaunchMode.externalApplication`). Existing call sites are unaffected
    // (Dart named constructor parameters, no positional/trailing-lambda ordering
    // hazard like Kotlin/Swift).
    ExternalUrlOpener? openExternalUrl,
    DefaultActivityFeed? feed,
    // win-claim-email-submit-flutter-template: DEPRECATED EMAIL-LESS seam. Kept
    // (shape unchanged) so existing hosts still compile — Dart does NOT allow a
    // fewer-parameter callback to be assigned to a wider function type, so this
    // parameter's type could not be swapped in place without BREAKING them
    // (design.md D5). Removal: next MAJOR. Use [claimContactSubmitter].
    // ignore: deprecated_member_use_from_same_package
    @Deprecated('EMAIL-LESS seam — 改用 claimContactSubmitter；下一個 major 移除。')
    AwardClaimSubmitter? claimSubmitter,
    /// win-claim-email-submit-flutter-template — contact-carrying claim seam. The
    /// host wires `controller.requestAwardClaim` (identical shape, tear-off works)
    /// so the email collected by the `LBWinSheet` reaches core. When omitted the
    /// submit is an inert no-op (headless) but the in-flight state machine still runs.
    AwardClaimContactSubmitter? claimContactSubmitter,
    EventJoinRequester? eventJoinRequester,
    GuestNameEditRequester? guestNameEditRequester,
    ViewCartRequester? viewCartRequester,
    GoodsTrackingSetter? setAwaitGoods,
    GoodsTrackingSetter? setNoticeGoods,
    AddToCartRequester? addToCartRequester,
    VideoLoadRequester? videoLoadRequester,
    MutedSetter? setMutedRequester,
    TogglePlayPauseRequester? togglePlayPauseRequester,
    VodSeekRequester? seekRequester,
    VodSeekRequester? seekByRequester,
  })  : _openInAppBrowser = openInAppBrowser ?? _defaultInAppBrowserOpener,
        _openExternalUrl = openExternalUrl ?? _defaultExternalUrlOpener,
        feed = feed ?? DefaultActivityFeed(),
        _eventJoinRequester = eventJoinRequester ?? ((_, __) {}),
        // live-activity-entry-flutter-template — [activeEvent] reuses the SAME
        // injected [EventJoinRequester] seam as [_eventJoinRequester] / [joinEvent]
        // (design.md D3): NOT a second typedef, NOT a second call-into-core path.
        // `DefaultActiveEvent`'s own constructor applies the identical inert
        // `(_, __) {}` no-op default when [eventJoinRequester] is omitted.
        activeEvent = DefaultActiveEvent(eventJoinRequester: eventJoinRequester),
        _guestNameEditRequester = guestNameEditRequester ?? (() {}),
        _viewCartRequester = viewCartRequester ?? ((_) {}),
        _videoLoadRequester = videoLoadRequester ?? ((_) {}),
        // flutter-player-toggle-mute-template — mute-intent forwarder. Default
        // no-op (headless-safe / unit tests); the `flutter-reference-ui`
        // container injects `(muted) => controller.setMuted(muted)`.
        _setMutedRequester = setMutedRequester ?? ((_) {}),
        // flutter-vod-playback-progress-template — VOD-2 control-exit
        // forwarders. Default no-op (headless-safe / unit tests); the
        // `flutter-reference-ui` container injects the real
        // `controller.togglePlayPause()` / `.seek(...)` / `.seekBy(...)`
        // closures (EXACT parity with the mute-forwarder wiring above).
        _togglePlayPauseRequester = togglePlayPauseRequester ?? (() {}),
        _seekRequester = seekRequester ?? ((_, {liveStatus, duration}) {}),
        _seekByRequester = seekByRequester ?? ((_, {liveStatus, duration}) {}),
        // product-sheet-stack-template — route-B add-to-cart delegate. Default
        // delegates to the core SDK endpoint; the host may override to route
        // through its own player ref. Tests inject a capturing / throwing fake.
        // MUST NOT build HTTP in the template (mirrors goodsTracking setAwait).
        _addToCartRequester =
            addToCartRequester ?? ((opts) => LivebuySDK.addToCart(opts)),
        // Default delegates the toggle to the core SDK endpoint (fire-and-forget);
        // the host may override to route through its own player ref. Tests inject
        // a capturing fake.
        goodsTracking = DefaultGoodsTracking(
          setAwait: setAwaitGoods ?? ((gpn, enabled) {
            LivebuySDK.setAwaitGoods(gpn, enabled);
          }),
          setNotice: setNoticeGoods ?? ((gpn, enabled) {
            LivebuySDK.setNoticeGoods(gpn, enabled);
          }),
        ),
        winClaim = DefaultWinClaim(
          // win-claim-email-submit-flutter-template: the host wires
          // `claimContactSubmitter: controller.requestAwardClaim` so the email
          // collected by `LBWinSheet` reaches core. `claimSubmitter` is the
          // DEPRECATED EMAIL-LESS seam, still forwarded for source compatibility
          // (contact is necessarily lost on that path). Neither supplied → the
          // submit is an inert no-op (headless).
          // ignore: deprecated_member_use_from_same_package
          submitter: claimSubmitter,
          contactSubmitter: claimContactSubmitter,
        ) {
    // #3 — surface backend layout keys this template version doesn't recognise.
    DefaultLayoutKeys.logUnknown('player', sdkConfig.layout?.player);
  }

  /// §2 — core delivered a personalized win (`showWin` / `WIN_RECEIVED`). Adds
  /// the win-tier item to the merged feed AND the winner to the unclaimed set
  /// (two independent records — §2). Host-owned activity is excluded from the
  /// feed by [DefaultActivityFeed] but the unclaimed entry still tracks it.
  void handleWin(String text, LBWinner winner) {
    feed.onWin(text, winner);
    winClaim.onWin(winner);
  }

  /// `VIDEO_SWITCH` — reset the per-video-session family-2 overlay so the next video
  /// starts clean: clear the merged feed + the win-claim unclaimed entry / result +
  /// the active-event snapshot / joined set (live-activity-entry-flutter-template)
  /// (parity with iOS `handleVideoSwitch`). Each `clear()` fires its own coalesced
  /// notification; the reference-ui re-reads the now-empty state. Also resets the
  /// per-session backlog-ingested flag so the next video's first round re-shows its
  /// history backlog (chat-history-dedupe-template).
  void handleVideoSwitch() {
    feed.clear();
    winClaim.clear();
    activeEvent.clear();
    _hasIngestedBacklog = false;
  }

  // chat-history-dedupe-template — cursor-based backlog 分流 (取代會誤殺後台刻意重送之真實通知的內容指紋
  // 去重)。core 每份 `LBPollResponse` 帶 `isBacklogReplay`，序列化於 POLL_RECEIVED `is_backlog`。

  /// Per-session flag — set once the first backlog round has been ingested into the feed; a later
  /// backlog REPLAY (cursor reset / re-enter) is then skipped. Reset on [handleVideoSwitch].
  bool _hasIngestedBacklog = false;

  /// Pure decision: should this poll round's feed buckets be ingested? `!isBacklogReplay` (a
  /// non-backlog round always ingests — real new messages incl. 後台 deliberate re-sends) OR
  /// `!alreadyIngestedBacklog` (the FIRST backlog round seeds the history). Unit-testable; parity
  /// iOS / Android / RN `shouldIngestPoll`.
  static bool shouldIngestPollDecision(
          bool isBacklogReplay, bool alreadyIngestedBacklog) =>
      !isBacklogReplay || !alreadyIngestedBacklog;

  /// Instance gate over [shouldIngestPollDecision] using the per-session [_hasIngestedBacklog]
  /// flag. Marks the flag once the FIRST backlog round is ingested so subsequent backlog replays
  /// skip. Returns whether `TemplateAttachment` should route this round's feed buckets.
  bool shouldIngestPoll(bool isBacklogReplay) {
    final ingest = shouldIngestPollDecision(isBacklogReplay, _hasIngestedBacklog);
    if (isBacklogReplay && ingest) _hasIngestedBacklog = true;
    return ingest;
  }

  /// §1 — core delivered a `showJoin` (poll `user[]`). Merges an 入場-tier item
  /// into the feed (excluded when the host owns activity). Parity with iOS/Android
  /// `handleJoin` / `handleShowJoin`.
  void handleJoin(String text) => feed.onJoin(text);

  /// §1 — core delivered a `showPurchase` (poll `rush[]`). Merges a 購買-tier item.
  void handlePurchase(String text) => feed.onPurchase(text);

  /// §1 — a chat message (poll `push[]`). Merges a chat row into the SAME feed
  /// model (data-layer merge only — NOT written back into the ChatView source).
  void handleChat(String userName, String text) => feed.onChat(userName, text);

  /// §1 — a poll `push[]` row → merged feed. A core event-BEGIN push
  /// (`eid > 0 && (ek 非空 || at == 'begin')`) is surfaced as an INDEPENDENT
  /// event-join item (host draws `LBEventJoinLine`); everything else — including
  /// event-END and ordinary pushes — stays a plain chat row.
  void handlePush({
    required String userName,
    required String text,
    int? eid,
    String? ek,
    String? at,
    String? color,
    String? ct,
    String? p,
    // chat-message-taxonomy ⑤ — 已格式化開賣價（onsale 商品開賣卡現價，權威輸出欄，非上游 `p`）。
    String? price,
    // chat-message-kind ⑤ — 判型 wire 字串（narrate/comment/host/host_reply/ai_reply/onsale/event；
    // 未知直通 raw）。新核心一律送；舊核心缺 kind 時退回既有 color 反推（backward-compat）。
    String? kind,
    // 主播 / AI 回覆的被回覆引用內容（backend `LBPushMsg.reply`），獨立字串。
    String? reply,
  }) {
    // event-join-cta-isset-ek（push.ek 版）：`kind == 'event'` 活動公告（**含 event-end**）最先判定 →
    // 獨立 event-join 項；舊核心無 kind 時退回 ek/at 偵測（向後相容）。CTA keyword 來源 = messages `push.ek`
    // （後台「ek isset 才顯示 CTA」契約，與 push 同筆同步到達，MUST NOT 改用 goods event[]）。begin/end 由
    // `ek` isset 與否自然分流：isset → 非空 keyword → CTA；unset → '' → 純公告（reference-ui 依非空 gate CTA）。
    final isEvent = (eid != null && eid > 0) &&
        (kind == 'event' || (ek != null && ek.isNotEmpty) || at == 'begin');
    if (isEvent) {
      feed.onEventJoin(eid: eid!, keyword: ek ?? '', text: text);
      return;
    }
    if (kind != null && kind.isNotEmpty) {
      // chat-message-kind ⑤ — 依 `kind` 判型路由（停止 color 反推）。parity iOS / RN `handlePush`。
      switch (kind) {
        case 'narrate':
          // 觀眾選購（`#66F796`, ty=ds）= 社會認同廣播，**性質同 join / purchase、非主播、非介紹中**。
          // （舊版誤把 `#66F796` 當「介紹中」走 onIntro，本批次語意校正為 browse tier。）
          feed.onNarrate(text);
          break;
        case 'onsale':
          // onsale 商品開賣改用主播訊息氣泡（isHost）。text 直顯後端組裝完整文案；name（= `userName`，
          // 即 push.name 主播名）；空 text 不 append（不出空氣泡）。取代既有 productSale 商品開賣卡路由。
          // reference-ui 既有 `.chat`(isHost:true) 渲染為主播氣泡，無需渲染層改動。Parity iOS / Android / RN。
          // dead-onsale-productsale-feed-flutter-template — `onProductSale` producer 與
          // `openProductSaleByName` / `matchSaleProduct` exit 已移除；`LBFeedKind.productSale` enum +
          // `LBFeedItem.productSale` factory + `price` 欄暫留（跨層共用，reference-ui 仍有 no-op case，
          // 完整移除需跨層 change）。
          if (text.isNotEmpty) feed.onChat(userName, text, isHost: true);
          break;
        case 'comment':
          // 一般用戶 / 訪客留言 → chat row 帶暱稱，isHost=false，不去重。
          feed.onChat(userName, text);
          break;
        case 'host':
        case 'host_reply':
        case 'ai_reply':
        case 'event':
          // 主播訊息 / 活動結束：帶 event / promo metadata（`eid>0` / `ct` / `p`）→ DE-DUPED 系統
          // 通知；其餘主播留言 → chat row 帶暱稱 + 角色 metadata。維持既有去重語意。
          if (isSystemNoticePush(eid: eid, color: color, ct: ct, p: p)) {
            feed.onSystemNotice(text);
          } else {
            final isAI = kind == 'ai_reply';
            final isReply = kind == 'host_reply' || kind == 'ai_reply';
            final r = (isReply && reply != null && reply.isNotEmpty) ? reply : null;
            feed.onChat(userName, text, isHost: true, isAI: isAI, replyText: r);
          }
          break;
        default:
          // .join / .purchase / .win 不會落 push 桶；未知 kind → 保守當 chat。
          feed.onChat(userName, text);
      }
      return;
    }
    // backward-compat（舊核心未送 kind）：保留既有 color 反推路徑。
    if (color == DefaultActivityFeed.productPushColor) {
      // 商品推播 (`#66F796`, e.g.「商品開賣 / 開始介紹」) → the dedicated `intro` activity row.
      // The `push[]` bucket has no stable id, so a backend re-send on an adjacent poll would
      // duplicate it — `onIntro` routes through the same DE-DUPED activity path so it shows once.
      feed.onIntro(text);
    } else if (isSystemNoticePush(eid: eid, color: color, ct: ct, p: p)) {
      // Remaining system notice (event-end `eid>0` / promo `ct` / `p`) — DE-DUPED chat row so a
      // re-send shows once. Free user chat (below) stays un-deduped.
      feed.onSystemNotice(text);
    } else {
      feed.onChat(userName, text);
    }
  }

  /// Whether a (non-event-begin, non-product-push) `push[]` row is a SYSTEM / 事件 / 促銷 notice
  /// rather than free user chat — used to route it through the DE-DUPED
  /// [DefaultActivityFeed.onSystemNotice] path. Flagged by event metadata (`eid > 0`, e.g.
  /// event-end / event-tied), OR promo metadata (`ct` / `p`). NOTE: the product-push color
  /// ([DefaultActivityFeed.productPushColor], spec §PollManager fan-out) is handled BEFORE this
  /// check in [handlePush] (→ the `intro` activity row), so it is NOT part of this predicate.
  /// Ordinary user chat carries none of these → stays un-deduped. Static for testability.
  static bool isSystemNoticePush({int? eid, String? color, String? ct, String? p}) {
    return (eid != null && eid > 0) ||
        (ct != null && ct.isNotEmpty) ||
        (p != null && p.isNotEmpty);
  }

  /// Host-triggered「加入活動」intent for an event-join feed item. Calls the
  /// injected event-join requester (which calls the player's `requestEventJoin`
  /// → core emits `eventJoinIntent`; if the host intercepts it, the host fulfils
  /// the join) and OPTIMISTICALLY marks the item joined (core has no "join
  /// succeeded" callback). MUST NOT auto-`sendChat`.
  void joinEvent(int eid, String keyword) {
    _eventJoinRequester(eid, keyword);
    feed.markJoined(eid);
  }

  /// auth-gate-template-state — an un-intercepted `AUTH_REQUIRED` arrived. Sets
  /// the single latest auth-gate state (excluded when the host owns the gate).
  /// Reads snake_case wire (`trigger_action` / `product_id` / `video_id`).
  void handleAuthRequired(Map<String, Object?> params) =>
      authGate.recordRequired(params);

  /// auth-gate-template-state — an `AUTH_STATE_CHANGED` notification arrived.
  /// Updates the identity-label AND, on `logged_in`, clears the auth-gate prompt
  /// (two independent view-models → each fires its own single notification).
  /// Reads snake_case wire (`state` / `display_name`); `resumed_action` ignored.
  void handleAuthStateChanged(Map<String, Object?> params) {
    final st = params['state'] as String?;
    identityLabel.update(st, params['display_name'] as String?);
    if (st == 'logged_in') authGate.clearOnLogin();
  }

  /// Host-triggered「請求改名」intent (guest態). Forwards to the injected
  /// requester (which calls the core exit emitting `GUEST_NAME_EDIT_REQUEST` —
  /// passthrough, non-navigation, no auto-PiP). Inert no-op when no requester was
  /// injected. The template draws NO rename UI and changes NO event semantics.
  void requestGuestNameEdit() => _guestNameEditRequester();

  /// Host-dismiss clear for the auth-gate prompt (symmetric with
  /// [DefaultErrorState.clear]).
  void clearAuthGate() => authGate.clear();

  // swipe-navigate-flutter-template — prev/next adjacent-video navigation.

  /// Host-fed prev/next adjacent-video nav targets (the host resolves
  /// `channel.prev.first?.id` / `channel.next.first?.id` from its own channel —
  /// the Flutter core does NOT bridge `LBChannel` to Dart; host-fed like
  /// `handleHeaderChrome` / `handleEndScreen`). Diff-then-notify inside the
  /// view-model (one real change → one notify on [navigation]).
  void handleNavTargets({String? prevVideoId, String? nextVideoId}) =>
      navigation.setNavTargets(
        prevVideoId: prevVideoId,
        nextVideoId: nextVideoId,
      );

  /// Switch to the previous adjacent video (reference-ui上滑手勢 / host). Calls the
  /// injected [VideoLoadRequester] with [DefaultPlayerNavigation.prevVideoId];
  /// no-op when `prevVideoId == null` (no previous video) or the requester is
  /// unwired (default no-op).
  void navigateToPrev() {
    final id = navigation.prevVideoId;
    if (id != null) _videoLoadRequester(id);
  }

  /// Switch to the next adjacent video (reference-ui下滑手勢 / host). Calls the
  /// injected [VideoLoadRequester] with [DefaultPlayerNavigation.nextVideoId];
  /// no-op when `nextVideoId == null` (no next video) or the requester is unwired.
  void navigateToNext() {
    final id = navigation.nextVideoId;
    if (id != null) _videoLoadRequester(id);
  }

  // await-toggle-and-notice-tab-template-state — goods-tracking + notice-tab.

  /// Seed a product's initial 到貨追蹤 / 補貨通知 flags. Host-fed because Flutter's
  /// `LBProduct` does not carry `isAwait` / `isAwaitNotice` (host reads them from
  /// its own data, like moment-state). Non-clobbering (a known key wins).
  void seedGoodsTracking(String goodsGpn,
          {required int isAwait, required int isAwaitNotice}) =>
      goodsTracking.seed(goodsGpn, isAwait: isAwait, isAwaitNotice: isAwaitNotice);

  /// Host toggle 到貨追蹤 (type=1): optimistic flip of ONLY the await flag, then
  /// delegate to `setAwaitGoods`.
  void toggleAwait(String goodsGpn) => goodsTracking.toggleAwait(goodsGpn);

  /// Host toggle 補貨通知 (type=2): optimistic flip of ONLY the notice flag.
  void toggleNotice(String goodsGpn) => goodsTracking.toggleNotice(goodsGpn);

  /// `AWAIT_GOODS_CHANGED` (notify) → correct the await flag (authoritative).
  /// Reads snake_case wire (`goods_gpn` / `enabled`).
  void handleAwaitGoodsChanged(Map<String, Object?> params) {
    final gpn = params['goods_gpn'] as String?;
    if (gpn == null) return;
    goodsTracking.applyAwaitBroadcast(gpn, params['enabled'] == true);
  }

  /// `NOTICE_GOODS_CHANGED` (notify) → correct the notice flag.
  void handleNoticeGoodsChanged(Map<String, Object?> params) {
    final gpn = params['goods_gpn'] as String?;
    if (gpn == null) return;
    goodsTracking.applyNoticeBroadcast(gpn, params['enabled'] == true);
  }

  /// Host-fed VideoInfoPanel notice texts (from its channel). idempotent.
  void handleChannelNotices(
          {required String systemNotice, required String notice}) =>
      noticeTab.injectNotices(systemNotice, notice);

  /// Host opens the notice tab (no-op when not openable).
  void openNoticeTab() => noticeTab.openNoticeTab();

  /// Host closes the notice tab.
  void closeNoticeTab() => noticeTab.closeNoticeTab();

  /// Map a typed core [LBError] into the host-bindable error-state (kind +
  /// failed phase). The host wires its `LivebuyPlayer.onError` here (Flutter's
  /// unified bridge listener does not carry the cross-platform error type — see
  /// `DefaultErrorState` doc). core stays headless; the template only maps.
  void handleError(LBError error) => errorState.recordError(error);

  /// §4 — map a core `awardClaimResult` into the result-state model and, on a
  /// claimed result, decrement the unclaimed entry for [winnerId].
  void handleAwardClaimResult({
    required LBAwardClaimStatus status,
    required String awardType,
    int? eventId,
    String? awardCode,
    String? winnerId,
  }) {
    winClaim.onAwardClaimResult(
      status: status,
      awardType: awardType,
      eventId: eventId,
      awardCode: awardCode,
      winnerId: winnerId,
    );
  }

  late final EffectiveConfig _effectiveConfig =
      EffectiveConfig(sdkConfig, hostOptions);

  /// VIDEO_STATE_CHANGE — SDK is headless; host provides overlay UI. Drives:
  /// (1) error-state clearing — when the player LEAVES `error` (host re-loaded)
  /// the error-state clears so the host dismisses `LBPErrorScreen`; (2) the
  /// StartScreen phase mapping (D2) — auto-wired so the host's splash dismisses
  /// with zero extra bridge code. `splash` requires [_hasStart] (set via
  /// [handleStartUrl]); without it the phase goes loading → done (never splash).
  void handlePlayerStateChange(String state) {
    assert(() {
      debugPrint('[DefaultTemplate] playerState: $state');
      return true;
    }());
    // upcoming-intro-template — cache the canonical state so handleUpcoming (the host
    // calls it on channel load, right after this state callback) can derive `upcoming`.
    _lastState = state;
    errorState.handleStateChange(state);
    startScreen.handleStateChange(state, hasStart: _hasStart);
    // end-screen-no-countdown — the end screen is visible ⟺ the player is in the
    // `endScreenShown` sub-state (the native core enters it on live end REGARDLESS of
    // next/hot, #3). Flutter does NOT bridge momentState, so endScreenVisible is derived
    // from the bridged player-state string (equivalent to iOS deriving it from
    // momentState.endScreenShown). ORTHOGONAL to the auto-next countdown.
    endScreen.setVisible(state == 'endScreenShown');
  }

  /// Host supplies `channel.start` (the opening MP4 URL) so the StartScreen
  /// phase can honour 「splash only when start non-empty」 (D2). Call before /
  /// alongside the state route; empty / null → no-splash path. Re-applies the
  /// last state through the phase mapping so a late-arriving start URL still
  /// surfaces splash. expose-player-moment-state-template; host-wired (D8).
  void handleStartUrl(String? startUrl) {
    _hasStart = startUrl != null && startUrl.trim().isNotEmpty;
  }

  /// upcoming-intro-template — host feeds the upcoming-relevant channel fields
  /// (from the core bridge's `LBPlayerChannelInfo` via `onChannelChange`) so the
  /// template can derive the [upcoming] view-model. Call on channel load, alongside
  /// the state route. Derives (parity iOS / Android):
  ///   • `active`       = the cached `lastState == "awaitingLive"`;
  ///   • `introPlaying` = `lastState == "startScreenPlaying" && hasStart &&
  ///     isUpcomingChannel`, where `hasStart = start 非空`,
  ///     `isUpcomingChannel(liveStatus, type) = liveStatus == 0 && type == 2`（後端 scheduled-live
  ///     訊號，rb-flutter-upcoming-intro-type / 問題 7；取代未來 publishAt heuristic、去 DateTime.now()
  ///     → 預計開播時間過了仍維持 introPlaying）;
  ///   • `scheduledStartAt` = `publishAt` (verbatim — the template MUST NOT parse);
  ///   • `cover` = `cover` (verbatim — the reference-ui paints it).
  /// `hasStart` is sourced from `channel.start` (parity 4788fae — NOT
  /// `momentState.startUrl`): it refreshes [_hasStart] AND re-applies the StartScreen
  /// splash phase so a late-arriving start URL surfaces splash. Diff-then-notify
  /// inside the view-models (one real change → one notify each). Inert before any
  /// state callback (`lastState == "loading"` → active / introPlaying false).
  /// [type] is the backend channel `type` (host-fed); default `-1` keeps existing callers
  /// non-upcoming (back-compat) until they forward the channel `type`.
  void handleUpcoming({
    required String publishAt,
    required String cover,
    required String start,
    required int liveStatus,
    int type = -1,
  }) {
    _hasStart = start.trim().isNotEmpty;
    // Re-apply the StartScreen splash with the fresh channel.start (parity 4788fae).
    startScreen.handleStateChange(_lastState, hasStart: _hasStart);
    final upcomingChannel = isUpcomingChannel(liveStatus, type);
    upcoming.apply(
      active: _lastState == 'awaitingLive',
      introPlaying:
          _lastState == 'startScreenPlaying' && _hasStart && upcomingChannel,
      scheduledStartAt: publishAt,
      cover: cover,
    );
  }

  /// Reset the upcoming view-model (+ its derivation inputs) for a new video /
  /// teardown (parity with [resetCartForSession] — the Flutter template has no
  /// aggregate `clear()`; per-view-model session resets are the convention). The
  /// host calls this on `unload` / hot-switch so a stale 直播預告 chrome does not
  /// linger on the next video.
  void resetUpcomingForSession() {
    _lastState = 'loading';
    _hasStart = false;
    upcoming.apply(
      active: false,
      introPlaying: false,
      scheduledStartAt: '',
      cover: '',
    );
  }

  /// EndScreen `next` / `hot` (host feeds its end-screen data on `endScreenShown`).
  /// expose-player-moment-state-template (D3); host-wired (D8).
  void handleEndScreen(List<LBEndNavItem> next, List<LBEndHotItem> hot) =>
      endScreen.setEnd(next, hot);

  /// Mirror one core auto-next countdown tick (`remain` + `active`). total is
  /// derived at the inactive→active edge inside the view-model (D3).
  void handleAutoNextTick(int remain, bool active) =>
      endScreen.tick(remain, active);

  /// User cancelled the auto-next (`Player.cancelAutoNext()` / empty `next`).
  void handleAutoNextCancel() => endScreen.cancel();

  /// ProductOverlay snapshot — host feeds the core `/sdk/video/goods` refresh
  /// (the template does NOT re-poll — D4). The host passes the single
  /// `narrate_status==2` product as [active] (Flutter `LBProduct` has no
  /// narrate_status field). Diff-then-notify inside the view-model. The
  /// OperationPanel bag-count is DERIVED from the SAME snapshot (no second
  /// products copy — player-chrome-template D2), so it stays in sync here.
  void handleProducts(List<LBProduct> products, {LBProduct? active}) {
    productOverlay.handleSnapshot(products, active: active);
    operationRail.handleBagCount(products.length);
    // minicart-peek-add-only (tmpl-ios-remove-minicart-peek-fallback): the mini-cart
    // peek is populated ONLY by a successful route-B add (see addToCart), NOT by the
    // in-narration `active` product. The 講解中商品 is already shown by the pinned card
    // (LIVE) / now-introducing card (VOD); seeding the peek with it duplicated that
    // surface (same MiniCart component) and leaked the VOD-only peek into LIVE. The
    // prior `active` fallback setPeek is removed.
  }

  /// PlayerHeader subscribe state (host echoes after subscribe success / from
  /// `channel.shop.is_subscribe`).
  void handleHeaderSubscribed(bool isSubscribed) =>
      header.setSubscribed(isSubscribed);

  /// PlayerHeader viewer count (host echoes `pv_num`).
  void handleViewerCount(int viewerCount) => header.setViewerCount(viewerCount);

  /// PlayerHeader mute flag — host echoes alongside `controller.setMuted` (the
  /// Flutter player exposes only the mute INTENT, no mute-state callback; D5).
  /// player-chrome-template (D2): the OperationPanel side-rail mirrors the SAME
  /// muted truth (single source — both PlayerHeader and side-rail echo here).
  void handleMuted(bool muted) {
    header.setMuted(muted);
    operationRail.setMuted(muted);
  }

  /// Host/reference-ui-callable mute that closes the Flutter mute-wiring gap
  /// (flutter-player-toggle-mute-template, parity iOS `setMuted` / Android
  /// `setMuted`): it forwards the intent to the core player via the injected
  /// [MutedSetter] (`LivebuyPlayerController.setMuted` → the active engine —
  /// IVS / AVPlayer, the audio path that actually un/mutes the stream) AND
  /// mirrors the presentation `muted` flag ([handleMuted]) from the SAME call, so
  /// the header / side-rail never diverge from the engine. The presentation-only
  /// [handleMuted] seam above stays the auto-muted / host-echo entry; this is the
  /// exit the tap-to-unmute gesture / host drive so the player actually produces
  /// sound. The Flutter template holds NO native player ref, so the forward is
  /// the injected [MutedSetter] (EXACT parity with Android's injected requester),
  /// wired by the `flutter-reference-ui` container at attach.
  void setMuted(bool muted) {
    _setMutedRequester(muted); // core: routes to the active engine (IVS / AVPlayer)
    handleMuted(muted); // presentation: PlayerHeader + side-rail mirror
  }

  /// Toggle mute relative to the current presentation truth ([header] `.muted`).
  /// Convenience for the tap-to-unmute gesture / a mute button — flips and
  /// forwards in one call (parity iOS / Android `toggleMute`,
  /// `setMuted(!currentMuted)`).
  void toggleMute() {
    setMuted(!header.muted);
  }

  /// VOD-2 control exit (flutter-vod-playback-progress-template, parity iOS
  /// `player.togglePlayPause()`): forwards the play/pause-toggle intent to the
  /// core via the injected [TogglePlayPauseRequester]
  /// (`LivebuyPlayerController.togglePlayPause()`). Pure forward — template
  /// MUST NOT redo any gating (there is none for this command). Unwired
  /// (default) requester is an inert no-op (headless-safe).
  void togglePlayPause() => _togglePlayPauseRequester();

  /// VOD-2 control exit (flutter-vod-playback-progress-template, parity iOS
  /// `player.seek(seconds:)`): forwards an ABSOLUTE seek to the core via the
  /// injected [VodSeekRequester] (`LivebuyPlayerController.seek(...)`).
  /// `liveStatus` / `duration` are passed through VERBATIM — the template does
  /// NOT derive them from its own [header].isLive / [playbackProgress].duration;
  /// the caller supplies them to opt into the core's `vodScrubAllowed` gate
  /// (gating itself lives entirely in core — template MUST NOT redo it).
  /// Unwired (default) requester is an inert no-op (headless-safe).
  void seek(double seconds, {int? liveStatus, double? duration}) =>
      _seekRequester(seconds, liveStatus: liveStatus, duration: duration);

  /// VOD-2 control exit (flutter-vod-playback-progress-template, parity iOS
  /// `player.seekBy(_:)`): forwards a RELATIVE seek to the core via the
  /// injected [VodSeekRequester] (`LivebuyPlayerController.seekBy(...)`) — a
  /// SEPARATE injected closure from [seek] (independent wiring, same param
  /// pass-through contract). Unwired (default) requester is an inert no-op
  /// (headless-safe).
  void seekBy(double seconds, {int? liveStatus, double? duration}) =>
      _seekByRequester(seconds, liveStatus: liveStatus, duration: duration);

  /// SubtitleTrack availability + toggle state (host knows `is_subtitle` from
  /// `/sdk/video` and its own toggle via `SubtitleTrack.setEnabled`).
  void handleSubtitle({required bool available, required bool enabled}) =>
      subtitle.setAvailability(available: available, enabled: enabled);

  /// SubtitleTrack channel-static half (flutter-subtitle-template-wiring) — the host
  /// (whatever constructs `LivebuyPlayerCore(...)`, i.e. reference-ui's drop-in container)
  /// wires `onSubtitleChange: (info) => template.handleSubtitleChannelInfo(available:
  /// info.available, url: info.url)`. Updates `subtitle.available` / `subtitle.url` while
  /// PRESERVING `subtitle.enabled` (an independent source — the runtime CC toggle, see
  /// [handleSubtitleToggle]). Also mirrors `available` into the side-rail's subtitle item
  /// (parity iOS `handleMomentState`'s single `s.subtitleAvailable` feeding both `subtitle
  /// .handle(...)` and `operationRail.handleEnablement(...)` from the SAME snapshot) — this
  /// is the fix for the CC pill never appearing (`operationRail`'s only OTHER feed path,
  /// `handleRailEnablement`, is not wired in production reference-ui today).
  void handleSubtitleChannelInfo({required bool available, required String url}) {
    subtitle.setAvailability(available: available, enabled: subtitle.enabled, url: url);
    operationRail.handleSubtitleAvailable(available);
  }

  /// SubtitleTrack runtime CC toggle (flutter-subtitle-template-wiring) — routed from the
  /// unified `SUBTITLE_TOGGLE` event by [TemplateAttachment] (the ONE internal
  /// `LivebuySDK.setListener(...)` subscriber this package owns). Routes THROUGH the existing
  /// [handleSubtitle] seam, reading the CURRENT `subtitle.available` (single source of truth,
  /// no extra cached field) to preserve it — `url` is likewise preserved (unchanged by
  /// [handleSubtitle]'s 2-arg signature).
  void handleSubtitleToggle(bool enabled) =>
      handleSubtitle(available: subtitle.available, enabled: enabled);

  // player-chrome-template — PlayerHeader top-bar chrome / OperationPanel
  // side-rail / VideoInfoPanel info-tab host-fed wiring (D3 / D2 / D4 / D6).

  /// PlayerHeader top-bar chrome (D3) — host feeds the host-pill fields from its
  /// `channel` (title / shop.name / shop.logo / share_url) once channel loads.
  /// Lives on the EXISTING [header] view-model (pure添欄). `momentState` MUST NOT
  /// carry these (double-source). One channel-load → one notify.
  void handleHeaderChrome({
    required String title,
    required String hostName,
    required String shopLogo,
    required String shareUrl,
    bool isLive = false,
    // 回放（已結束直播）flag — host-fed (`type == 3 || (type == 2 && liveStatus == 3)`,
    // 用 top-level `isFinishedLiveReplay(type, liveStatus)` 計算). parity iOS/Android/RN.
    bool isFinishedLiveReplay = false,
  }) =>
      header.setChrome(
        title: title,
        hostName: hostName,
        shopLogo: shopLogo,
        shareUrl: shareUrl,
        isLive: isLive,
        isFinishedLiveReplay: isFinishedLiveReplay,
      );

  /// VOD playback progress (VOD-2) — host echoes a progress snapshot
  /// (position / duration / isPlaying / isReplay). `isReplay` (a LIVE stream
  /// scrubbed behind the live edge) drives the reference-ui bottom-bar replay
  /// variant. One change → one notify (diff on the state).
  ///
  /// flutter-vod-playback-progress-template: in production a host typically
  /// wires this directly from the REAL native-backed
  /// `LivebuyPlayerCore(onPlaybackProgressChange: template.handlePlaybackProgress)`
  /// bridge callback added by `flutter-vod-playback-progress-core` (driven by
  /// the `'playbackProgress'` case on `EventChannel('tv.livebuy/player_events')`)
  /// — this method's signature and diff-then-notify contract are unchanged;
  /// only the typical data source is now a real bridge event instead of an
  /// arbitrary host echo. See [togglePlayPause] / [seek] / [seekBy] for the
  /// VOD-2 control-exit counterparts.
  void handlePlaybackProgress({
    required double position,
    required double duration,
    required bool isPlaying,
    required bool isReplay,
  }) =>
      playbackProgress.setProgress(
        position: position,
        duration: duration,
        isPlaying: isPlaying,
        isReplay: isReplay,
      );

  /// OperationPanel side-rail enablement (D2) — host feeds the derived flags from
  /// its `channel` (live_status / guest_comment / shop.service_link) +
  /// `momentState` (is_subtitle). `goods` / `like` / `share` / `more` are always
  /// enabled. One change → one notify.
  void handleRailEnablement({
    required bool chatEnabled,
    required bool subtitleAvailable,
    required bool serviceLinkAvailable,
    required bool guestEditAvailable,
  }) =>
      operationRail.handleEnablement(
        chatEnabled: chatEnabled,
        subtitleAvailable: subtitleAvailable,
        serviceLinkAvailable: serviceLinkAvailable,
        guestEditAvailable: guestEditAvailable,
      );

  /// Update ONLY the LIVE chat-enabled flag (問題4) — a mid-live `guest_comment` change relayed by
  /// the native core via POLL_RECEIVED; the other rail flags are preserved. Lets RN/Flutter apply a
  /// backend「開啟訪客留言」change WITHOUT a re-enter.
  void handleChatEnabled(bool chatEnabled) => operationRail.handleChatEnabled(chatEnabled);

  /// OperationPanel bag-count (D2) — host echoes `products.count` alongside the
  /// products snapshot (DERIVED from ProductOverlay's products — no second copy).
  void handleBagCount(int count) => operationRail.handleBagCount(count);

  /// OperationPanel heart-burst (D2) — one core `likePerformed` / unified
  /// `VIDEO_LIKE` arrived (愛心 API succeeded) → bump the monotonic burst tick so
  /// the host plays the heart-burst animation. The template draws NO animation,
  /// does NOT call like itself (real like goes via `simulateLikeTap` + throttle).
  void handleLikePerformed() => operationRail.handleLikePerformed();

  /// VideoInfoPanel info-tab fields (D4) — host feeds the「直播資訊」fields from its
  /// `channel` (title / publish_at / shop.name / shop.intro / shop.logo). EXCLUDES
  /// `description` (LBChannel has no such field — R6). `isSubscribed` is NOT fed
  /// here — info-tab reads the SAME truth as [header] (single-source).
  void handleInfo({
    required String title,
    required String publishAt,
    required String shopName,
    required String shopIntro,
    required String shopLogo,
  }) =>
      infoTab.handleInfo(LBInfoTabFields(
        title: title,
        publishAt: publishAt,
        shopName: shopName,
        shopIntro: shopIntro,
        shopLogo: shopLogo,
      ));

  /// VideoInfoPanel tab switch (D4) — `info` always selectable; `notice` only when
  /// [noticeTab].canOpen is true (else no-op). When the current tab is `notice`
  /// and 公告轉空, the active tab auto-falls-back to `info` (handled inside
  /// [DefaultInfoTab] via a notice-tab listener — no extra wiring needed here).
  void handleSelectInfoTab(LBInfoPanelTab tab) => infoTab.selectTab(tab);

  /// DISMISS_REQUEST — Navigator.pop (Task 6.5)
  void handleDismissRequest(BuildContext context) {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  /// PRODUCT_TAP — `diversion == 1` routes the purchase-page URL by
  /// `LBURLOpenPolicy.decide` (url-open-host-routing-template-flutter):
  /// `LBURLOpenTarget.inApp` → the in-app browser seam, `.external` → the
  /// system URL router seam, unopenable (`null`) → a safe no-op. The template
  /// MUST NOT hard-code「一律 in-app」or「一律 external」at this call site — see
  /// [_openResolvedUrl]. `diversion == 0` opens the host-bindable
  /// product-detail sheet stack (product-sheet-stack-template, D1): maps the
  /// full `LBProduct` into [productSheet], remaps [variantPicker] from its
  /// specOptions / specifications, and recomputes [qtyStepper] bounds from the
  /// effective stock (selection / qty are RESET on a new product). Only reached
  /// when the host did NOT intercept `productTap`; when [hostOwnsCart] is true
  /// (host took over via route A) the detail sheet is NOT set. Interception
  /// order is unchanged: intercept (upstream) → verdict → present.
  ///
  /// The full `LBProduct` is host-wired (the bridge `PRODUCT_CLICK` carries only
  /// `{product_id, video_id}` — too light; D7 / D8), exactly like the other
  /// host-fed moment-state typed sources.
  Future<void> handleProductTap({
    required dynamic product,
    required int diversion,
  }) async {
    if (diversion == 1) {
      await _openResolvedUrl(product?.diversionUrl as String? ?? '');
      return;
    }
    // diversion == 0 — in-app product panel → product-detail sheet stack.
    if (hostOwnsCart) return; // host took over (route A) — exclude.
    if (product is! LBProduct) return;
    _openProductDetail(product);
  }

  /// The single URL-open exit for the `diversion == 1` purchase-page flow
  /// (url-open-host-routing-template-flutter). Decides via core
  /// [LBURLOpenPolicy.decide] and dispatches to exactly one of the two
  /// injected seams. MUST use [LBURLOpenDecision.url] (never [rawUrl]) so
  /// callers never see a parser differential; `null` (not openable) is a SAFE
  /// no-op — no seam call, no exception, no blank browser.
  ///
  /// The `switch` below is a STATEMENT with no `default` clause — verified
  /// (this change's own disposable probe, see design.md decision D-B) to be a
  /// HARD compile error in this project
  /// (`non_exhaustive_switch_statement`, package language version `3.0`, both
  /// `switch` statement AND expression forms are equally hard errors here) when
  /// [LBURLOpenTarget] gains a member this helper does not handle. Statement
  /// form is chosen only because it mirrors this codebase's existing
  /// enum-switch convention (e.g. `LBActivityTier.rank` in
  /// `default_activity_feed.dart`), not because the expression form would be
  /// any less safe.
  Future<void> _openResolvedUrl(String rawUrl) async {
    final decision = LBURLOpenPolicy.decide(rawUrl);
    if (decision == null) return;
    final resolved = decision.url.toString();
    switch (decision.target) {
      case LBURLOpenTarget.inApp:
        await _openInAppBrowser(resolved);
      case LBURLOpenTarget.external:
        await _openExternalUrl(resolved);
    }
  }

  /// Map the product into the detail sheet + reset variant/qty (D1). The
  /// selection RESET (variant picker remap) + qty bounds recompute are
  /// orchestrated here because the sibling view-models are template-held.
  void _openProductDetail(LBProduct product) {
    // Opening a (different) detail clears a stale needs-login gate from a prior product's
    // add (parity iOS/Android/RN sheet-open reset).
    _addToCartNeedsLogin = false;
    // cart-add-loading-state-flutter: 開新詳情清除 stale in-flight（與 needs-login 並列）。
    _addToCartInFlight = false;
    productSheet.openDetail(product, _currentOtherGoods);
    variantPicker.reset(product.specOptions, product.specifications);
    // No spec chosen yet → bounds derive from the product stock (D3).
    qtyStepper.recomputeBounds(
      stock: product.stock,
      soldOut: product.soldOut,
      resetQty: true,
    );
  }

  /// Host supplies the shop id (route-B `shop_id`) from its `channel` (the
  /// Flutter bridge `LBProduct` has no shopId). Host-wired typed source, like
  /// other channel-derived fields (header chrome / info-tab).
  void setShopId(String shopId) => _shopId = shopId;

  /// Host picked variant option [optionIndex] in group [groupIndex]. Updates the
  /// selection and re-clamps qty to the newly-resolved spec's stock (D2 / D3).
  void selectVariant(int groupIndex, int optionIndex) {
    variantPicker.selectVariant(groupIndex, optionIndex);
    _reclampQtyForSelection();
  }

  /// Recompute qty bounds from the current selection: prefer the selected spec's
  /// stock, else the product stock (D3). Keeps qty (a spec switch is not a fresh
  /// open) but clamps it into the new range.
  void _reclampQtyForSelection() {
    final detail = productSheet.detail;
    if (detail == null) return;
    final spec = variantPicker.selectedSpec;
    final stock = spec?.stock ?? detail.stock;
    final soldOut = (spec != null && spec.stock <= 0) ? 1 : detail.soldOut;
    qtyStepper.recomputeBounds(stock: stock, soldOut: soldOut);
  }

  /// qty-stepper intents (host binds `LBPQtyStepper` ±). Clamp inside the model.
  void setQty(int value) => qtyStepper.setQty(value);
  void incQty() => qtyStepper.incQty();
  void decQty() => qtyStepper.decQty();

  /// Host「關閉商品明細 sheet」intent — clears the product-detail state
  /// ([DefaultProductSheet.detail] → null). The reference-ui sheet's dismiss wires
  /// here so the template's `detail` returns to null; otherwise [_openProductDetail]
  /// is diff-then-notify (re-opening the SAME product is a no-op), so a closed sheet
  /// could not be re-opened by tapping the same product again until a DIFFERENT
  /// product changed `detail`. [DefaultProductSheet.clearDetail] notifies its own
  /// listeners iff it cleared something (no-op when already null) — exactly the
  /// notification the bound `ListenableBuilder` needs. Parity with iOS
  /// `DefaultPlayerTemplate.closeProductDetail()` (expose-close-product-detail-template).
  void closeProductDetail() => productSheet.clearDetail();

  /// mini-cart intents. [openMiniCartDetail] re-opens the peeked product's
  /// detail sheet (host must re-feed the full `LBProduct`; the peek is light).
  void dismissMiniCart() => miniCart.dismissMiniCart();

  /// cart-CTA「開啟購物車」passthrough intent (D4, view-cart-event-flutter-template).
  /// The template owns NO checkout; it forwards to the injected [ViewCartRequester]
  /// with the current product detail's id (商品詳情頁 CTA) or `null` (商品列表底部
  /// CTA → the core seam omits the `product_id` key). The host wires the requester
  /// to the player ref's `requestViewCart(productId:)` (emit `VIEW_CART`). When no
  /// requester is injected (default), this is a safe no-op.
  void openCart() {
    _viewCartRequester(productSheet.detail?.productId);
  }

  /// Reset the per-session cart-CTA count (teardown / new video, D4 / OQ2).
  void resetCartForSession() => cartCTA.resetForSession();

  /// product-sheet-stack-template (D5) — route-B add-to-cart intent. Gates on:
  /// (a) [hostOwnsCart] (host took over via route A) → MUST NOT delegate;
  /// (b) product has spec groups but selection is incomplete (`selectedSpec ==
  /// null`) → MUST NOT delegate, sets [needsVariantSelection];
  /// (c) `qty max == 0` (out of stock) → MUST NOT delegate.
  /// Otherwise builds `LBAddToCartOptions` (goodsId / num=qty /
  /// specificationId=selectedSpecificationId, omitted when no spec) and delegates
  /// the injected requester (route B). On success sets the mini-cart peek AND
  /// increments the cart-CTA count (two state mutations → the host's listeners
  /// fire, coalesced per the existing ChangeNotifier fan-in); on failure sets
  /// [addToCartFailed] WITHOUT touching the count. MUST NOT build HTTP itself.
  Future<void> addToCart() async {
    _addToCartFailed = false;
    _addToCartNeedsLogin = false;
    _needsVariantSelection = false;
    final detail = productSheet.detail;
    if (detail == null) return; // no open detail — nothing to add.
    if (hostOwnsCart) return; // route A took over — no route-B delegation.

    // Gate: has spec groups but selection incomplete → 請選規格.
    if (variantPicker.hasGroups && variantPicker.selectedSpec == null) {
      _needsVariantSelection = true;
      return;
    }
    // Gate: out of stock (qty max == 0) → block.
    if (qtyStepper.max == 0) return;

    // cart-add-loading-state-flutter: 通過全部 guards → 即將委派 requester。在第一個 `await` 之前
    // 同步設 in-flight true（reference-ui `final f = addToCart()` 回來時可立即讀以顯示 loading）。
    // 純欄位、不 notify（template 非 ChangeNotifier；呈現由 container 驅動）。
    _addToCartInFlight = true;
    final specId = variantPicker.selectedSpecificationId;
    final options = LBAddToCartOptions(
      shopId: _shopId,
      goodsId: int.tryParse(detail.productId),
      num: qtyStepper.qty,
      specificationId: specId == null ? null : int.tryParse(specId),
      // cart-add-tier2-unify：帶入當前影片短碼 → core CART_ADD_REQUEST.video_id。
      videoId: _currentVideoId,
    );
    try {
      await _addToCartRequester(options);
      // Success → mini-cart peek + cart-CTA count (D5). Two ChangeNotifier
      // mutations; the host re-reads on each (coalesce is per-notifier).
      miniCart.setPeek(LBMiniCartPeek(
        productId: detail.productId,
        name: detail.name,
        priceShow: detail.priceShow,
        soldOut: detail.soldOut,
      ));
      cartCTA.incrementOnAdd();
      // cart-add-loading-state-flutter: 成功 → 解除 in-flight。
      _addToCartInFlight = false;
    } catch (e) {
      // Branch the error (cart-add-tier2-unify): a 30s 重複加購 dedupe-hit
      // ([LBErrorCartAddDeduplicated]) → 已加入 UX (refresh mini-cart peek, count
      // UNCHANGED, no failure flag); the core「needs login」signal (LBErrorServer code 401
      // for an empty buy_no) → needs-login (reference-ui login gate); any other error →
      // genuine failure (retry banner). parity iOS/Android/RN.
      if (isAddToCartDeduplicated(e)) {
        // Dedupe-hit「已加入購物車」: refresh the peek but DO NOT increment the CTA
        // count (the original add already bumped it) and DO NOT set the failure flag.
        miniCart.setPeek(LBMiniCartPeek(
          productId: detail.productId,
          name: detail.name,
          priceShow: detail.priceShow,
          soldOut: detail.soldOut,
        ));
      } else if (isAddToCartAuthRequired(e)) {
        _addToCartNeedsLogin = true;
      } else {
        _addToCartFailed = true;
      }
      // cart-add-loading-state-flutter: 任一結果分支完成 → 解除 in-flight。
      _addToCartInFlight = false;
    }
  }

  // Layout well-known keys (Task 6.7)

  String get productOverlayPosition =>
      _effectiveConfig.layoutValue('productOverlay_position', 'bottom') as String;

  String get productOverlayStyle =>
      _effectiveConfig.layoutValue('productOverlay_style', 'sheet') as String;
}

/// Visibility cascade for operation panel buttons (Task 6.6).
class DefaultOperationPanel {
  final bool chatVisible;
  final bool productVisible;
  final bool announcementVisible;

  DefaultOperationPanel({
    required SDKConfig sdkConfig,
    LBUIOptions? hostOptions,
  })  : chatVisible = ConfigMerger.effectiveVisibility(
          sdkValue: sdkConfig.visibility?.chat,
          hostValue: hostOptions?.visibility?.chat,
          templateDefault: true,
        ),
        productVisible = ConfigMerger.effectiveVisibility(
          sdkValue: sdkConfig.visibility?.productOverlay,
          hostValue: hostOptions?.visibility?.productOverlay,
          templateDefault: true,
        ),
        // #1 — the 公告 (announcement) button is gated by `videoInfoPanel`, NOT
        // `activityNotification` (Visibility Cascade spec / D1). `activityNotification`
        // controls the ActivityNotification component itself and has no panel button.
        announcementVisible = ConfigMerger.effectiveVisibility(
          sdkValue: sdkConfig.visibility?.videoInfoPanel,
          hostValue: hostOptions?.visibility?.videoInfoPanel,
          templateDefault: true,
        );
}

/// Default Widget template event handler (Task 6.5).
class DefaultWidgetTemplate {
  final SDKConfig sdkConfig;
  final LBUIOptions? hostOptions;

  final WidgetVideoTapRequester _videoTapRequester;

  /// widget-content-template — host-bindable widget content view-model. Mirrors
  /// the core `LivebuyWidget` read surface (`videos` / `mode` / `currentPage` /
  /// `lastPage` / `liveVideo` / `isClosed`-derived `minimized`) + the web-embed
  /// colors (raw passthrough from widget-bridge-color-core) + `productCard`
  /// (raw passthrough from widget-product-card-bridge-flutter, arriving on the
  /// snapshot wire rather than the colors call). Host binds
  /// [DefaultWidgetContent.current] with `ListenableBuilder` to draw `widgets.jsx`.
  /// The template draws NO cards / rows / floating window / minimized bubble.
  ///
  /// On Flutter the content is HOST-FED off the per-view widget bridge (D7): the
  /// host wires the content snapshot via [handleWidgetSnapshot] and the colors via
  /// [handleWidgetColors] (off `LivebuyWidgetController.onWidgetResponse`), exactly
  /// like it wires the player moment / chrome typed sources. READ surface public;
  /// ingestion `@internal`.
  final DefaultWidgetContent content = DefaultWidgetContent();

  DefaultWidgetTemplate({
    required this.sdkConfig,
    this.hostOptions,
    WidgetVideoTapRequester? videoTapRequester,
  }) : _videoTapRequester = videoTapRequester ?? ((_) {}) {
    // #3 — surface backend widget layout keys this template version doesn't recognise.
    DefaultLayoutKeys.logUnknown('widget', sdkConfig.layout?.widget);
  }

  late final EffectiveConfig _effectiveConfig =
      EffectiveConfig(sdkConfig, hostOptions);

  /// Widget card tap → full-screen open Player intent (parity with
  /// iOS/Android/RN `DefaultWidgetTemplate.handleVideoTap`). Forwards the tapped
  /// card's [videoId] to the host-wired requester so the host navigates/presents
  /// the full-screen Player. Inert no-op when no requester was injected
  /// (headless-safe). MUST NOT render any Player pixels — the full-screen Player
  /// page is drawn by the host.
  void handleVideoTap(String videoId) {
    _videoTapRequester(videoId);
  }

  // widget-content-template — host-fed widget content wiring (D7).

  /// Host feeds the widget content snapshot read from the snake_case widget
  /// bridge wire (`videos` / `current_page` / `last_page` / `mode` /
  /// `is_closed` / `live_video` / `product_card`). Mirrors the core
  /// `LivebuyWidget` state into
  /// [content]; `minimized` is derived from `mode == floating && is_closed`;
  /// `product_card` is raw passthrough (missing → `null`, never defaulted to
  /// `inside`). Diff-then-notify (one real change → one notify). MUST NOT render
  /// pixels.
  void handleWidgetSnapshot(Map<String, Object?> params) =>
      content.handleWidgetSnapshot(params);

  /// Host feeds the web-embed colors off the core
  /// `LivebuyWidgetController.onWidgetResponse` (LBWidgetColors —
  /// widget-bridge-color-core). Raw passthrough; never interpreted. Missing colors
  /// → the host simply never calls this and [content] keeps the core defaults
  /// (`widgetColor = 1` / `widgetBgcolor = null`).
  void handleWidgetColors(LBWidgetColors colors) =>
      content.handleWidgetColors(colors);

  /// Host echoes a floating-widget close / re-expand (`simulateClose` / re-open),
  /// re-deriving `floating` ⇄ `minimized` (D3). No-op when not floating-derived.
  void handleFloatingClosed(bool isClosed) =>
      content.handleFloatingClosed(isClosed);

  // Widget layout well-known keys (Task 6.7)

  String get carouselEffect =>
      _effectiveConfig.widgetLayoutValue('carousel_effect', 'slide') as String;

  bool get carouselAutoPlay =>
      _effectiveConfig.widgetLayoutValue('carousel_autoPlay', false) as bool;

  int get gridColumns =>
      _effectiveConfig.widgetLayoutValue('grid_columns', 2) as int;
}
