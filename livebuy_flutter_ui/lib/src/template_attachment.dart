import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

import 'default_template.dart';

// MARK: - livebuy-ui-event-wiring-template — Flutter attach wiring (design D3)
//
// Unlike iOS / Android (which hook the core's `onInstantiate` and split events
// into two routes — typed callbacks + an aux listener), the Flutter UI layer
// lives entirely in Dart and cannot hold the native Player instance directly.
// It therefore subscribes through the single bridge event channel via
// `LivebuySDK.setListener(...)` (already exposed by `flutter/lib/src/
// event_listener.dart`). One unified listener carries every SDK event.
//
// Lifecycle (design D3):
//   - host mount   → `attach()`   → `LivebuySDK.setListener(handler)`
//   - host unmount → `detach()`   → `LivebuySDK.setListener(null)`
//
// The handler routes the events the Default template cares about
// (DISMISS_REQUEST / WIN_RECEIVED / VIDEO_STATE_CHANGE / POLL_RECEIVED /
// PRODUCT_CLICK) to the matching template handler, then replies
// `passthrough`/`acknowledge` so the template's default-UI side effect never
// shadows the host's own interaction handling.

/// Bridges the unified SDK event stream to a [DefaultPlayerTemplate] for the
/// Flutter UI layer. Created by the host's player widget on mount; subscribes
/// via [LivebuySDK.setListener] on [attach] and tears the subscription down on
/// [detach] (design D3 — no native hook on Flutter).
class TemplateAttachment {
  /// FORMAL HOST-ACCESS POINT (expose-default-template-bindable-state, design
  /// D2): the host obtains the Default template for a Player by holding the
  /// [TemplateAttachment] its player widget created and reading this getter.
  /// Through it the host reads the bindable, observable state —
  /// [DefaultPlayerTemplate.feed] (merged feed `items`, a `ChangeNotifier`) and
  /// [DefaultPlayerTemplate.winClaim] (unclaimed `count` / winners + claim
  /// result state, a `ChangeNotifier`) — and binds them with `ListenableBuilder`.
  /// The template's constructor and `handle*` event methods are NOT for host
  /// use (the host consumes state; it does not build the instance or feed
  /// events). Flutter's accessor idiom is host-held (no global per-Player
  /// lookup), matching the four-platform parity contract.
  final DefaultPlayerTemplate template;

  /// `BuildContext` resolver for `DISMISS_REQUEST` (`Navigator.pop`). Optional so
  /// unit tests can drive routing without a widget tree; null → dismiss no-op.
  final BuildContext? Function()? contextProvider;

  /// Test-visible counter: how many `WIN_RECEIVED` events have been observed.
  /// The §2 unclaimed-entry behaviour now lives on the template; this counter
  /// is retained for the existing wiring tests that assert the route delivers.
  int winReceivedCount = 0;

  bool _attached = false;

  TemplateAttachment({
    required this.template,
    this.contextProvider,
  });

  /// Subscribe to the unified SDK event stream (host mount).
  /// Idempotent — calling twice keeps a single subscription.
  void attach() {
    if (_attached) return;
    _attached = true;
    LivebuySDK.setListener(_onSdkEvent);
    // player-default-unmuted — seed the presentation `muted` flag to UNMUTED at
    // attach (design parity with iOS `TemplateAttachment.swift`'s
    // `template.handleMuted(false)` / RN `handleMutedChange(false)`). This is the
    // explicit "attach = re-seed as unmuted" contract: with the new `false`
    // constructor default it is a no-op for a fresh template, but it re-seeds an
    // EXISTING template passed via `options.template` (which may still carry a
    // stale `muted == true`). One-shot at attach only — in-place switches flow
    // through the `VIDEO_SWITCH` event (no re-attach), so this seed never resets
    // the mute preference on a switch.
    template.handleMuted(false);
  }

  /// Unsubscribe from the unified SDK event stream (host unmount).
  /// Idempotent — safe to call when not attached.
  void detach() {
    if (!_attached) return;
    _attached = false;
    LivebuySDK.setListener(null);
  }

  /// True while a bridge subscription is active.
  bool get isAttached => _attached;

  /// PUBLIC forwarding seam (`add-flutter-dropin-container-event-forward-template`):
  /// lets a second, external `LivebuySDK.setListener` caller (e.g. a reference-ui
  /// drop-in container's own wrapper listener, which necessarily REPLACED this
  /// attachment's bridge subscription — `setListener` is a single global slot)
  /// hand one event back to this attachment's template without re-subscribing.
  /// Delegates unconditionally to the same private router [_onSdkEvent] the live
  /// bridge subscription itself uses (design D1 — "one router, two entry
  /// points"): does NOT gate on [_attached] / [isAttached], so it still routes
  /// after [detach] (the instance method is independent of the bridge
  /// subscription's lifecycle; only the subscription itself is torn down).
  Future<LBEventReply> handleEvent(LBSdkEvent event) => _onSdkEvent(event);

  /// Route one unified event to the Default template. Notification-type events
  /// reply `acknowledge` (a no-op for the SDK) so the template's default UI side
  /// effect coexists with the host's primary interaction flow.
  Future<LBEventReply> _onSdkEvent(LBSdkEvent event) async {
    switch (event.eventName) {
      case LBEvent.videoStateChange:
        // Drives error-state clearing AND the StartScreen moment phase
        // (expose-player-moment-state-template, D8) — `handlePlayerStateChange`
        // now also calls `startScreen.handleStateChange`, so the splash phase is
        // auto-wired here with ZERO new bridge code. The OTHER four moment
        // view-models (EndScreen / ProductOverlay / PlayerHeader / SubtitleTrack)
        // are NOT bridged on Flutter (`momentState` is host-owned) → the host
        // feeds them via the public `handle*` typed methods on the template
        // (echoes mute via `handleMuted`, supplies `channel.start` via
        // `handleStartUrl`, plus end-screen / products / header / subtitle typed
        // sources), EXACTLY like it wires `LivebuyPlayer.onError` → `handleError`.
        // No bridge channel is invented for `momentState` (intentional, D8).
        final state = event.params['state'];
        if (state is String) template.handlePlayerStateChange(state);
        return LBEventReply.acknowledge;

      case LBEvent.dismissRequest:
        final context = contextProvider?.call();
        if (context != null) template.handleDismissRequest(context);
        return LBEventReply.acknowledge;

      case LBEvent.winReceived:
        // §2 — a personalized win arrived. Build the winner from the flat
        // WIN_RECEIVED params ({id, event_id, title, award_type, award_name, award_code})
        // and feed it to the template (merged feed item + unclaimed entry).
        winReceivedCount += 1;
        final winner = _winnerFromWinReceived(event.params);
        if (winner != null) {
          final text = '${winner.title} 中獎了!';
          template.handleWin(text, winner);
        }
        return LBEventReply.acknowledge;

      case LBEvent.awardClaimResult:
        // §4 — map the claim result into the template's result-state model.
        //
        // DELIBERATELY passes NO `winnerId`: this router does NOT read a winner id
        // out of the wire params — `DefaultWinClaim.lastSubmittedWinnerId` is the
        // single source (parity iOS / RN). Re-verified under
        // win-claim-email-submit-flutter-template: Android hit a key drift here
        // (`AwardClaimResultMapper.claimedWinnerId` read `params["id"]` while the
        // wire key is `winner_id`; `id` belongs to WIN_RECEIVED). Flutter cannot hit
        // it because it never touches that key — do NOT "helpfully" start reading
        // one without checking the authoritative AWARD_CLAIM_RESULT params.
        template.handleAwardClaimResult(
          status: LBAwardClaimStatus.fromWire(
              (event.params['status'] as String?) ?? ''),
          awardType: (event.params['award_type'] as String?) ?? '',
          eventId: (event.params['event_id'] as num?)?.toInt(),
          awardCode: event.params['award_code'] as String?,
        );
        return LBEventReply.acknowledge;

      case LBEvent.activeEventStarted:
        // live-activity-entry-flutter-template — core fire-once push announcing a
        // new active event. Build the flat wire params ({id, title, keyword?,
        // duration, surplus, award}) into an LBActiveEvent (keyword absent key →
        // null) and hand it to the template's merged view-model. This is a
        // STANDALONE event name — it is NOT routed through the POLL_RECEIVED push
        // buckets (`_routePollBuckets`), so it does not interfere with that path.
        // Notification event (acknowledge); the template draws NO pixels.
        template.activeEvent.handleActiveEventStarted(
          LBActiveEvent.fromMap(event.params),
        );
        return LBEventReply.acknowledge;

      case LBEvent.pollReceived:
        // §1 — route the poll buckets the core now ships in the unified
        // POLL_RECEIVED params (poll-received-unified-params-core): user[]→join,
        // rush[]→purchase, push[]→chat, all merged into the feed model (NOT
        // double-written into the ChatView source). win[] is NOT routed here —
        // personalized wins come via WIN_RECEIVED. Acknowledge so the host's
        // listener flow is unaffected.
        // chat-history-dedupe-template — cursor-based backlog 分流：以 core 的 `is_backlog` 訊號 +
        // per-session 旗標 gate feed 灌入——後續輪真實新訊息（含後台刻意重送）一律灌、首輪 backlog 首次
        // 灌當歷史首屏、已 ingest 過的 backlog 重放整批 skip（換片漏 clear / 重入疊加）。判定只看 cursor +
        // 旗標，NOT 內容（內容去重會誤殺後台刻意重送的真實通知）。
        final bool isBacklog = event.params['is_backlog'] == true;
        if (template.shouldIngestPoll(isBacklog)) {
          _routePollBuckets(event.params);
        }
        // 置頂留言（`data.top`，正交於 push 桶）維持每輪呼叫（冪等，不受 backlog gate 影響——以當前狀態覆蓋）。
        template.handlePinned(event.params['top']);
        // 問題4 — the native core relays the CURRENT channel `guest_comment` + `live_status` on every
        // POLL_RECEIVED (the live channel-settings refresh updates them mid-live). Re-derive
        // `chatEnabled` (`live_status == 1 && guest_comment == 1`) so a backend「開啟訪客留言」change
        // enables the guest's chat WITHOUT a re-enter. Guarded on presence so an older native (no
        // field) never clobbers the rail. Idempotent (diff-then-notify in the rail).
        final Object? gc = event.params['guest_comment'];
        if (gc != null) {
          final bool chatEnabled = (event.params['live_status'] as num?)?.toInt() == 1 &&
              (gc as num).toInt() == 1;
          template.handleChatEnabled(chatEnabled);
        }
        // 問題5 — the native core relays the CURRENT channel `notice` / `sys_notice` on every
        // POLL_RECEIVED (live-notice-poll-relay-core). Ingest it so the LIVE 公告 banner / notice tab
        // show on initial load AND update mid-live when 後台 changes the 公告 — Flutter has NO native
        // `onChannelRefresh` consumer (the native host ingests via that callback). Guarded on presence
        // so an older native (no field) never clobbers an existing 公告. `handleChannelNotices` →
        // `noticeTab.injectNotices` is idempotent (diff; empties collapse `canOpen`).
        final Object? noticeVal = event.params['notice'];
        final Object? sysNoticeVal = event.params['sys_notice'];
        if (noticeVal != null || sysNoticeVal != null) {
          template.handleChannelNotices(
            systemNotice: sysNoticeVal is String ? sysNoticeVal : '',
            notice: noticeVal is String ? noticeVal : '',
          );
        }
        return LBEventReply.acknowledge;

      case LBEvent.authRequired:
        // auth-gate-template-state — un-intercepted `AUTH_REQUIRED` → auth-gate
        // state. The Flutter UI subscribes through the SINGLE unified listener,
        // so this listener IS the unified listener: it MUST be NON-PRIMARY and
        // return `passthrough` (result:false) so it does NOT intercept and does
        // NOT change core's interception decision / `PendingAuthStore` write /
        // 30s replay / auto-PiP. host-takeover exclusion is the host-set
        // `authGate.hostOwnsAuthGate` flag (design D2), NOT this return value.
        // `handleAuthRequired` reads snake_case wire (trigger_action /
        // product_id / video_id).
        template.handleAuthRequired(event.params);
        return LBEventReply.passthrough;

      case LBEvent.authStateChanged:
        // auth-gate-template-state — notification event. Updates identity-label
        // and, on `logged_in`, clears the auth-gate prompt. Return value is
        // ignored (acknowledge). Reads snake_case wire (state / display_name);
        // `resumed_action` is intentionally NOT read.
        template.handleAuthStateChanged(event.params);
        return LBEventReply.acknowledge;

      case LBEvent.videoLike:
        // player-chrome-template (D6 / R5) — the愛心 API actually succeeded
        // (after the core 250ms throttle). Core dispatches `VIDEO_LIKE` { video_id }
        // on like-API success (the declared `LIKE_PERFORMED` event is NOT emitted
        // by core today — see player-chrome-template design), so the heart-burst
        // beat binds `VIDEO_LIKE`, parity with iOS/Android/RN. Bump the
        // OperationPanel heart-burst tick so the host plays the heart-burst
        // animation. The wire carries snake_case keys (`video_id`); we only need
        // the BEAT here, not the count, so the tick is a monotonic counter.
        // Notification event (acknowledge); the template draws NO animation and
        // does NOT call like itself.
        template.handleLikePerformed();
        return LBEventReply.acknowledge;

      case LBEvent.subtitleToggle:
        // flutter-subtitle-template-wiring — the runtime CC on/off toggle. Both native SDKs
        // dispatch `SUBTITLE_TOGGLE` { enabled: bool } through the generic EventDispatcher
        // (rb-flutter-subtitle-channel-bridge-core design.md already established this needs
        // zero bridge code — any host with `LivebuySDK.setListener(...)` installed already
        // receives it). Tolerant decode via equality (missing/non-bool → false) — NOT `as
        // bool?`, which only tolerates a NULL value; a wrong-typed non-null value (e.g. a
        // stray String) still throws on `as`, which `LivebuySDK._onMethodCall`'s outer
        // try/catch would silently swallow, turning the whole toggle into a no-op instead of
        // a safe `false`. Notification event (acknowledge); the template draws NO pixels.
        final enabled = event.params['enabled'] == true;
        template.handleSubtitleToggle(enabled);
        return LBEventReply.acknowledge;

      case LBEvent.awaitGoodsChanged:
        // await-toggle-and-notice-tab-template-state — authoritative 到貨追蹤
        // broadcast → correct the await flag. Notification event (acknowledge).
        // Reads snake_case wire (goods_gpn / enabled).
        template.handleAwaitGoodsChanged(event.params);
        return LBEventReply.acknowledge;

      case LBEvent.noticeGoodsChanged:
        // Authoritative 補貨通知 broadcast → correct the notice flag.
        template.handleNoticeGoodsChanged(event.params);
        return LBEventReply.acknowledge;

      case LBEvent.productClick:
        // PRODUCT_CLICK carries only `{product_id, video_id}` over the bridge —
        // too light for either the diversion URL-open path (routed by
        // LBURLOpenPolicy — url-open-host-routing-template-flutter; NOT always
        // in-app) OR the product-sheet-stack detail (both need the full
        // LBProduct). So the
        // template's productTap behaviour is HOST-WIRED: the host calls
        // `template.handleProductTap(product: <full LBProduct>, diversion: …)`
        // from its per-view `LivebuyPlayer.onProductTap` typed callback
        // (product-sheet-stack-template D7 / D8, exactly like the other moment /
        // chrome typed sources). Here we pass through so the host's primary
        // interception still wins and the SDK stays headless.
        return LBEventReply.passthrough;

      case LBEvent.videoSwitch:
        // activity-feed-clear-on-video-switch parity — core dispatched a real video
        // change ({from_video_id, to_video_id}; only fired when prev != new id, so
        // first-load / same-video retry never reach here). Reset the per-video-session
        // merged feed + win-claim entry so the next video starts clean. Notification
        // event (acknowledge); non-primary.
        //
        // activity-entry-video-switch-cache-and-hide-flutter — forward the wire's
        // `from_video_id` / `to_video_id` through so `activeEvent`'s per-videoId
        // switch cache can resolve immediately (tolerant decode: non-String / missing
        // → null, matching the existing `vid is String ? vid : null` convention below).
        final fromVideoId = event.params['from_video_id'];
        final toVideoId = event.params['to_video_id'];
        template.handleVideoSwitch(
          from: fromVideoId is String ? fromVideoId : null,
          to: toVideoId is String ? toVideoId : null,
        );
        return LBEventReply.acknowledge;

      case LBEvent.videoOpen:
        // restriction-gate-template parity — channel-apply carries the SOFT display-gate
        // `is_restriction` (additive param, int 0/1). Derive `isRestricted` (== 1; non-1 /
        // missing → false fail-open) so reference-ui overlays the upgrade mask. Flutter has
        // NO ingestChannel, so VIDEO_OPEN is the channel feed; the ValueNotifier handles
        // diff-then-notify. core does NOT block playback (soft gate). Notification event.
        template.applyRestriction(event.params['is_restriction'] == 1);
        // cart-add-tier2-unify — VIDEO_OPEN carries `video_id`; track it as the
        // template's currentVideoId so addToCart threads it into
        // CART_ADD_REQUEST.video_id (Flutter has no ingestChannel). pure assignment.
        final vid = event.params['video_id'];
        template.setCurrentVideoId(vid is String ? vid : null);
        return LBEventReply.acknowledge;

      default:
        // Every other event is owned by the host's primary listener.
        return LBEventReply.passthrough;
    }
  }

  /// Build an [LBWinner] from the flat `WIN_RECEIVED` params
  /// (`{id, event_id, title, award_type, award_name, award_code}`). Returns null
  /// when the participant ticket id is missing (nothing to track). Mirrors iOS
  /// `TemplateAuxListener.winner(from:)` (event_id / title, post LBWinner rename).
  static LBWinner? _winnerFromWinReceived(Map<String, Object?> p) {
    final id = p['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return LBWinner(
      id: id,
      eventId: (p['event_id'] as num?)?.toInt() ?? 0,
      title: (p['title'] as String?) ?? '',
      award: LBAward(
        type: (p['award_type'] as String?) ?? '',
        code: (p['award_code'] as String?) ?? '',
        name: (p['award_name'] as String?) ?? '',
      ),
    );
  }

  /// Route the unified `POLL_RECEIVED` buckets into the merged feed (§1):
  /// `user[]`→join, `rush[]`→purchase, `push[]`→chat. Tolerant — missing/empty
  /// buckets and items without a `text` are skipped (the bridge decodes params
  /// via `StandardMessageCodec`, so values arrive dynamically typed). `win[]` is
  /// intentionally NOT routed here (personalized wins arrive via `WIN_RECEIVED`).
  void _routePollBuckets(Map<String, Object?> params) {
    for (final item in _bucket(params['user'])) {
      final text = _str(item['text']);
      if (text != null) template.handleJoin(text);
    }
    for (final item in _bucket(params['rush'])) {
      final text = _str(item['text']);
      if (text != null) template.handlePurchase(text);
    }
    for (final item in _bucket(params['push'])) {
      final text = _str(item['text']);
      if (text != null) {
        // event-begin pushes (eid>0 && (ek非空 || at=='begin')) surface as
        // event-join items; everything else stays a plain chat row. handlePush
        // owns the split (the bridge decodes eid/ek/at dynamically typed).
        // color / ct / p are forwarded so handlePush can route SYSTEM / 商品推播 notices
        // (product-push color #66F796 / event / promo) through the de-duped path.
        template.handlePush(
          userName: _str(item['name']) ?? '',
          text: text,
          eid: (item['eid'] as num?)?.toInt(),
          ek: _str(item['ek']),
          at: _str(item['at']),
          color: _str(item['color']),
          ct: _str(item['ct']),
          p: _str(item['p']),
          // chat-message-taxonomy ⑤ — 已格式化開賣價（onsale 商品開賣卡現價，核心序列化提供）。
          price: _str(item['price']),
          // chat-message-taxonomy ⑤ — `kind` 判型 wire 字串（停止 color 反推）、`reply` 被回覆
          // 引用內容（主播 / AI 回覆引用框）。核心 pollReceivedEventParams 已序列化（缺則退回 color）。
          kind: _str(item['kind']),
          reply: _str(item['reply']),
        );
      }
    }
  }

  /// A `String` value or null (never throws on a non-string dynamic value).
  static String? _str(Object? v) => v is String ? v : null;

  /// Coerce a bucket param into an iterable of string-keyed maps, tolerating the
  /// dynamic shapes `StandardMessageCodec` produces (`List` of `Map`). Non-list
  /// inputs yield an empty iterable; non-map entries are dropped.
  static Iterable<Map<String, Object?>> _bucket(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)));
  }
}
