import 'package:flutter/foundation.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

// expose-player-moment-state-template — five player "moment" host-bindable
// view-models (behaviour / view-model layer; NO pixels).
//
// Spec: ui-template-foundation/spec.md § "Default Template Player Moment-State
// 暴露" (+ MODIFIED "Default Template Bindable State 變更通知").
// Design: design.md D1–D8. Depends on expose-player-moment-state-core (already
// applied: iOS/Android Player expose `momentState` + `onMomentStateChange`).
//
// HEADLESS: every class here is a READ-only view-model the host binds to draw
// the `moments.jsx` components (StartScreen / EndScreen / ProductOverlay /
// PlayerHeader / SubtitleTrack). The template renders NO pixels — it imports
// only `package:flutter/foundation.dart` (ChangeNotifier) + the core models;
// it has NO Widget subclass, NO `package:flutter/widgets.dart` import.
//
// Flutter wiring note (D8): `momentState` is NOT bridged to the Dart layer
// (intentional — the host owns the native Player; the Dart layer has only the
// unified bridge + per-view callbacks). So ALL five view-models are fed via the
// host-wired typed `handle*` methods on `DefaultPlayerTemplate`, EXACTLY like
// the error-state precedent (host wires `LivebuyPlayer.onError` → `handleError`).
// Only the StartScreen PHASE source is auto-wired, because
// `TemplateAttachment._onSdkEvent` already routes `VIDEO_STATE_CHANGE` →
// `handlePlayerStateChange`. The view-model SHAPE + notification behaviour are
// four-platform identical; only the ingestion wiring differs by platform event
// architecture (固有差異, not a behaviour divergence).
//
// Each view-model `extends ChangeNotifier` (Flutter's coalesced-notification
// idiom, parity with DefaultErrorState / DefaultActivityFeed / DefaultWinClaim):
// the host binds each with `ListenableBuilder` and `notifyListeners()` fires
// EXACTLY ONCE per real change (diff-then-notify — no spurious notify on an
// unchanged snapshot).

// ── 1. StartScreen ──────────────────────────────────────────────────────────

/// StartScreen lifecycle phase the host binds to pick the splash variant
/// (`LBPStartScreen` `phase`). Maps from the PLAYER STATE (D2), not a new state.
enum LBPStartPhase { loading, splash, buffering, done }

/// StartScreen phase view-model. The host binds [phase] to draw / dismiss the
/// opening splash. Phase is a mapping of the canonical player state +
/// `channel.start` presence (D2): `loading`→loading; `startScreenPlaying`→splash
/// (ONLY when `channel.start` non-empty); `buffering`→buffering; any main state
/// (playing / paused / ended / endScreenShown)→done. When `channel.start` is
/// empty the phase MUST NOT be splash (loading→done only).
class DefaultStartScreenState extends ChangeNotifier {
  LBPStartPhase _phase = LBPStartPhase.loading;

  /// Current StartScreen phase (init [LBPStartPhase.loading]).
  LBPStartPhase get phase => _phase;

  /// Map a canonical player-state name → phase and notify only on a real change.
  /// [hasStart] = `channel.start` non-empty (host-supplied — VIDEO_STATE_CHANGE
  /// does not carry it). When false, `startScreenPlaying` collapses to `done`.
  @internal
  void handleStateChange(String canonicalName, {required bool hasStart}) {
    final next = _mapPhase(canonicalName, hasStart: hasStart);
    if (next == _phase) return;
    _phase = next;
    notifyListeners();
  }

  static LBPStartPhase _mapPhase(String name, {required bool hasStart}) {
    switch (name) {
      case 'loading':
        return LBPStartPhase.loading;
      case 'buffering':
        return LBPStartPhase.buffering;
      case 'startScreenPlaying':
        return hasStart ? LBPStartPhase.splash : LBPStartPhase.done;
      default:
        // playing / paused / ended / endScreenShown / awaitingLive / error → done.
        return LBPStartPhase.done;
    }
  }
}

// ── 1b. Upcoming (直播預告) — parity iOS DefaultUpcomingState (eaa14c5 / 544d284) ─

/// Upcoming (直播預告 awaiting-live) view-model: `{ active, introPlaying,
/// scheduledStartAt, cover }`. The host binds it (`ListenableBuilder`) so the
/// reference-ui can compose the upcoming LIVE chrome. Parity with iOS
/// `DefaultUpcomingState` / Android `DefaultUpcomingState`.
///
///   • [active]          = awaiting-live countdown (直播預告, **not** playing a video).
///   • [introPlaying]    = the upcoming opening MP4 (intro preroll, `channel.start`)
///                         is playing → the reference-ui wears LIVE chrome over the
///                         intro video (VOD intro keeps `introPlaying == false`).
///   • [scheduledStartAt]= `channel.publish_at` verbatim (the template MUST NOT parse).
///   • [cover]           = `channel.cover` verbatim (the template MUST NOT load it;
///                         the reference-ui paints it as the countdown background).
///
/// Diff-then-notify: `notifyListeners()` fires EXACTLY ONCE per real change (no
/// spurious notify on an unchanged snapshot). HOST-FED via
/// `DefaultPlayerTemplate.handleUpcoming` (the Flutter core does NOT bridge the
/// full `LBChannel` to Dart — `upcoming-intro-core-flutter` forwards only the
/// upcoming fields as `LBPlayerChannelInfo`).
class DefaultUpcomingState extends ChangeNotifier {
  bool _active = false;
  bool _introPlaying = false;
  String _scheduledStartAt = '';
  String _cover = '';

  /// Awaiting-live countdown active (`lastState == "awaitingLive"`).
  bool get active => _active;

  /// The upcoming opening MP4 (intro) is playing (LIVE chrome over the intro).
  bool get introPlaying => _introPlaying;

  /// Scheduled start (`channel.publish_at` verbatim — the template MUST NOT parse).
  String get scheduledStartAt => _scheduledStartAt;

  /// Video cover URL (`channel.cover` verbatim — the countdown background).
  String get cover => _cover;

  /// Apply a derived upcoming snapshot. Notifies only when at least one of the four
  /// fields actually changed (diff-then-notify).
  @internal
  void apply({
    required bool active,
    required bool introPlaying,
    required String scheduledStartAt,
    required String cover,
  }) {
    if (active == _active &&
        introPlaying == _introPlaying &&
        scheduledStartAt == _scheduledStartAt &&
        cover == _cover) {
      return;
    }
    _active = active;
    _introPlaying = introPlaying;
    _scheduledStartAt = scheduledStartAt;
    _cover = cover;
    notifyListeners();
  }
}

/// Pure helper: whether [s] (backend `publish_at`, UTC+8 `"yyyy-MM-dd HH:mm:ss"`)
/// parses to a FUTURE instant. Empty / unparseable → false. [now] is injectable for
/// deterministic tests. Mirrors the iOS / Android template `publishAtInFuture`
/// (the core player's same-named helper is internal + unreachable from the template,
/// so the template carries its own copy). Pure string parse → no `intl` dependency.
bool publishAtInFuture(String s, {DateTime? now}) {
  if (s.trim().isEmpty) return false;
  final parts = s.split(' ');
  if (parts.length != 2) return false;
  final date = parts[0].split('-');
  final time = parts[1].split(':');
  if (date.length != 3 || time.length != 3) return false;
  final y = int.tryParse(date[0]);
  final mo = int.tryParse(date[1]);
  final d = int.tryParse(date[2]);
  final h = int.tryParse(time[0]);
  final mi = int.tryParse(time[1]);
  final se = int.tryParse(time[2]);
  if (y == null || mo == null || d == null || h == null || mi == null || se == null) {
    return false;
  }
  // Interpret the stamp as UTC+8: build the wall-clock instant in UTC then shift
  // back 8h to the real UTC instant (so the comparison is timezone-independent).
  final utcPlus8Wall = DateTime.utc(y, mo, d, h, mi, se);
  final instant = utcPlus8Wall.subtract(const Duration(hours: 8));
  final reference = (now ?? DateTime.now()).toUtc();
  return instant.isAfter(reference);
}

/// Pure helper: whether a channel is a 直播預告 (upcoming/scheduled-live) — `liveStatus == 0`
/// AND the backend's canonical scheduled-live signal **`type == 2`**. Clock-independent (no
/// `DateTime.now()`). Replaces the prior future-`publishAt` heuristic so a scheduled live whose
/// start time has PASSED but is not yet live stays upcoming, and a regular VOD (`type == 1`) never
/// misclassifies. Mirrors iOS / Android `isUpcomingChannel` (upcoming-intro-persist-after-schedule,
/// 問題 7).
bool isUpcomingChannel(int liveStatus, int type) => liveStatus == 0 && type == 2;

/// Pure helper: whether a channel is a 回放 (一場已結束的直播). 型別語意（與 iOS / Android / RN 一致，
/// 實測校正影片 `W4pqqM` 為 `type == 3` / `liveStatus == 3`）：**`type == 3` = 回放（已結束直播）**、
/// `type == 2` = 直播（預告 + 進行中）、`type == 1` = 點播 VOD。`liveStatus`：0=未直播 / 1=直播中 /
/// 3=已結束/回放。回 `true` 當且僅當 `type == 3`（回放型別，與 `liveStatus` 無關）OR
/// `type == 2 && liveStatus == 3`（剛結束、仍標記直播型別的邊界）；其餘 `false`（直播中
/// `liveStatus == 1`、預告 `type == 2 && liveStatus == 0`、純 VOD `type == 1`）。與 `isLive`
/// (`liveStatus == 1`) 互斥。host / bridge 由 channel 計算後經 `handleHeaderChrome(isFinishedLiveReplay:)`
/// 餵入。Mirrors iOS / Android / RN `isFinishedLiveReplay(type, liveStatus)`.
bool isFinishedLiveReplay(int type, int liveStatus) =>
    type == 3 || (type == 2 && liveStatus == 3);

// ── 2. EndScreen ─────────────────────────────────────────────────────────────

/// Template-owned light value type for an EndScreen `next[]` recommendation.
/// (`LBNavItem` does not exist in the Flutter core package — see file note 2;
/// keeping this self-contained stays template-layer-only and touches NO core.)
///
/// `shopName` / `duration` (seconds) carry the design's「{shopName} · {duration}」
/// preview meta line (`LBPEndScreen`, moments.jsx:321) — parity with the iOS
/// template's `LBNavItem` (which exposes `shopName` / `duration`). Both are host-fed
/// (the host populates them via `handleEndScreen`) and default to empty / 0 so
/// existing call sites stay source-compatible (purely additive).
@immutable
class LBEndNavItem {
  final String id;
  final String title;
  final String cover;
  final String shopName;
  final int duration;
  const LBEndNavItem({
    required this.id,
    required this.title,
    this.cover = '',
    this.shopName = '',
    this.duration = 0,
  });
}

/// Template-owned light value type for an EndScreen `hot[]` recommendation.
@immutable
class LBEndHotItem {
  final String id;
  final String title;
  final String cover;
  final int duration;
  const LBEndHotItem(
      {required this.id, required this.title, this.cover = '', this.duration = 0});
}

/// Auto-next countdown snapshot. [total] is captured at the inactive→active edge
/// and held constant while [remain] decrements each tick (D3).
@immutable
class LBEndCountdown {
  final int remain;
  final int total;
  const LBEndCountdown({required this.remain, required this.total});

  @override
  bool operator ==(Object other) =>
      other is LBEndCountdown && other.remain == remain && other.total == total;

  @override
  int get hashCode => Object.hash(remain, total);
}

/// EndScreen view-model: `next[]` / `hot[]` + an OPTIONAL auto-next [countdown]
/// (D3). `countdown` is non-null ONLY while the core-driven auto-next countdown
/// is active AND `next` is non-empty AND the user has not cancelled. `next` /
/// `hot` stay exposed even when `countdown == null` (host draws the 熱門 variant).
class DefaultEndScreenState extends ChangeNotifier {
  List<LBEndNavItem> _next = const [];
  List<LBEndHotItem> _hot = const [];
  LBEndCountdown? _countdown;
  bool _visible = false;

  /// Next-up recommendations (host draws regardless of countdown).
  List<LBEndNavItem> get next => List.unmodifiable(_next);

  /// Hot recommendations (host draws regardless of countdown).
  List<LBEndHotItem> get hot => List.unmodifiable(_hot);

  /// Auto-next countdown, or null when inactive / `next` empty / cancelled.
  LBEndCountdown? get countdown => _countdown;

  /// Whether the end screen should be shown at all (mirrors the player entering
  /// the `endScreenShown` sub-state). ORTHOGONAL to [countdown]: live end sets
  /// this true REGARDLESS of next/hot, so the no-countdown「直播已結束」end screen can
  /// render. `countdown != null` ⟹ `endScreenVisible == true`. The template drives
  /// it from the player state (`state == 'endScreenShown'`). Default false. Parity
  /// iOS / Android `endScreenVisible` / RN `visible`.
  bool get endScreenVisible => _visible;

  /// Set the end-screen visibility (template-driven from the player state).
  /// ORTHOGONAL to the countdown — leaving the end state hides it. Notifies only
  /// on a real change.
  @internal
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    notifyListeners();
  }

  /// Populate `next` / `hot` (host feeds its end-screen data on `endScreenShown`).
  @internal
  void setEnd(List<LBEndNavItem> next, List<LBEndHotItem> hot) {
    _next = List.of(next);
    _hot = List.of(hot);
    notifyListeners();
  }

  /// Mirror one core auto-next tick. [total] is captured at the inactive→active
  /// edge and held while [remain] decrements; countdown→null when !active OR
  /// `next` is empty (D3). Notifies only on a real change.
  @internal
  void tick(int remain, bool active) {
    LBEndCountdown? next;
    if (active && _next.isNotEmpty) {
      // Capture total at the inactive→active edge; hold it across ticks.
      final total = _countdown?.total ?? remain;
      next = LBEndCountdown(remain: remain, total: total);
    }
    if (next == _countdown) return;
    _countdown = next;
    notifyListeners();
  }

  /// User cancelled the auto-next (`Player.cancelAutoNext()`). countdown→null;
  /// `next` / `hot` remain exposed. No-op (no notify) when already null.
  @internal
  void cancel() {
    if (_countdown == null) return;
    _countdown = null;
    notifyListeners();
  }
}

// ── 3. ProductOverlay ────────────────────────────────────────────────────────

/// ProductOverlay view-model: the latest core `products` SNAPSHOT + the single
/// `narrate_status==2` in-narration [activeProduct] (nil when none) (D4).
/// DIFF-then-notify by product-id list + active id — products refresh every 5s,
/// so an unchanged snapshot MUST NOT notify (Risks / merged-feed discipline).
///
/// suppress-product-overlay-during-intro-flutter-template: while the intro MP4
/// preroll is playing (`DefaultPlayerTemplate.startScreen.phase == splash`),
/// the EXPOSED [products] / [activeProduct] read as empty / null regardless of
/// what has been fed via [handleSnapshot] — the raw snapshot is still buffered
/// internally (never cleared) so it can be restored the instant the intro ends,
/// with no re-fetch and no wait for the next poll tick. See [setIntroPlaying].
class DefaultProductOverlayState extends ChangeNotifier {
  List<LBProduct> _products = const [];
  LBProduct? _activeProduct;
  bool _introPlaying = false;

  /// Latest products snapshot (host binds to draw the sheet / banner). Reads as
  /// `[]` while the intro is playing (see [setIntroPlaying]) — the underlying
  /// buffer is untouched.
  List<LBProduct> get products =>
      _introPlaying ? const <LBProduct>[] : List.unmodifiable(_products);

  /// The single in-narration product (`narrate_status==2`), or null. Reads as
  /// `null` while the intro is playing (see [setIntroPlaying]).
  LBProduct? get activeProduct => _introPlaying ? null : _activeProduct;

  /// The currently-introducing product's id (= `activeProduct?.id`; LIVE
  /// `narrate_status == 2`, null when none). The reference-ui product LIST draws
  /// the「介紹中」banner on the row whose id matches this. Pure computed (no second
  /// state). Parity iOS / Android / RN `introducingProductId`. Reads off the
  /// GATED [activeProduct] (null while the intro is playing), so it collapses
  /// to null over the intro without any extra gating logic here.
  String? get introducingProductId => activeProduct?.id;

  /// `products` with the currently-introducing product (`activeProduct`) moved to
  /// the FRONT, preserving the relative order of the rest. When there is no active
  /// product (VOD / nothing introducing) this equals `products` unchanged. Pure
  /// computed (no second state). The reference-ui product LIST binds THIS so the
  /// introducing item sorts first — ORDERING is a data-layer responsibility;
  /// reference-ui MUST NOT re-sort. Parity iOS / Android / RN `productsIntroducingFirst`.
  /// Reads off the GATED [products] / [activeProduct] (both empty/null while the
  /// intro is playing), so it collapses to `[]` over the intro automatically.
  List<LBProduct> get productsIntroducingFirst {
    final source = products;
    final id = activeProduct?.id;
    if (id == null) return source;
    final idx = source.indexWhere((p) => p.id == id);
    if (idx < 0) return source;
    final ordered = List<LBProduct>.of(source);
    final item = ordered.removeAt(idx);
    ordered.insert(0, item);
    return List.unmodifiable(ordered);
  }

  /// Ingest a core products refresh. Flutter `LBProduct` has no `narrate_status`
  /// field, so the host passes [active] explicitly (file note 5). The internal
  /// buffer (`_products` / `_activeProduct`) is updated UNCONDITIONALLY — even
  /// while the intro is playing (suppress-product-overlay-during-intro-flutter-
  /// template, never cleared) — so the moment the intro ends, [products] /
  /// [activeProduct] can restore this exact data with no re-fetch. Notifies only
  /// when the EXPOSED value actually changes (see [_applyAndNotifyIfExposedChanged]):
  /// a same-shape refresh received while the intro is playing does not spuriously
  /// notify, since the exposed value stays empty/null either way.
  @internal
  void handleSnapshot(List<LBProduct> products, {LBProduct? active}) {
    _applyAndNotifyIfExposedChanged(() {
      _products = List.of(products);
      _activeProduct = active;
    });
  }

  /// Suppress-product-overlay-during-intro-flutter-template — toggle whether the
  /// opening MP4 preroll is currently playing. Host-driven via
  /// `DefaultPlayerTemplate` (never called directly by app hosts). While `true`,
  /// [products] / [activeProduct] expose empty/null regardless of the buffer;
  /// flipping back to `false` restores the buffer INSTANTLY (no re-fetch, no wait
  /// for the next products poll). No-op when the value does not actually change.
  @internal
  void setIntroPlaying(bool introPlaying) {
    if (introPlaying == _introPlaying) return;
    _applyAndNotifyIfExposedChanged(() {
      _introPlaying = introPlaying;
    });
  }

  /// Run [mutate], then `notifyListeners()` iff the EXPOSED [products] /
  /// [activeProduct] differ before vs. after — diff-then-notify on the exposed
  /// value (not the raw buffer), which is what makes both [handleSnapshot] and
  /// [setIntroPlaying] behave correctly during the intro: a buffer-only change
  /// while suppressed is silent, and un-suppressing with a non-empty buffer
  /// always notifies exactly once.
  void _applyAndNotifyIfExposedChanged(void Function() mutate) {
    final visibleBefore = products;
    final activeBeforeId = activeProduct?.id;
    mutate();
    final sameIds = _sameIds(visibleBefore, products);
    final sameActive = activeBeforeId == activeProduct?.id;
    if (sameIds && sameActive) return;
    notifyListeners();
  }

  static bool _sameIds(List<LBProduct> a, List<LBProduct> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }
}

// ── 4. PlayerHeader ──────────────────────────────────────────────────────────

/// PlayerHeader view-model: `{ isSubscribed, viewerCount, muted }` (D5) PLUS the
/// top-bar chrome fields `{ title, hostName, shopLogo, shareUrl }` added by
/// player-chrome-template (D3). `isSubscribed` mirrors the live subscribe state
/// (host echoes after subscribe success); `viewerCount` mirrors `pv_num`; `muted`
/// mirrors the player mute flag — `momentState` does NOT carry muted, so it is
/// host-echoed alongside `controller.setMuted` (file note 3). The chrome fields
/// (`title` = channel.title, `hostName` = channel.shop.name, `shopLogo` =
/// channel.shop.logo, `shareUrl` = channel.share_url) are host-fed from `channel`
/// once it loads — `momentState` MUST NOT carry them (avoid double-source).
/// Defaults [muted] = false (unmuted / sound on by default — the core main
/// playback starts UNMUTED per `player-default-unmuted-core`; the presentation
/// flag mirrors the core `userMuted` single truth). Flips on the first mute
/// echo. This state has NO `clear()` — `muted` only changes via [setMuted], so
/// an in-place switch (which never touches the header) naturally preserves the
/// mute preference. Each field diff-notifies (one mutation → one
/// notify).
class DefaultPlayerHeaderState extends ChangeNotifier {
  bool _isSubscribed = false;
  int _viewerCount = 0;
  bool _muted = false; // unmuted / sound on by default.

  // player-chrome-template (D3) — top-bar chrome host-pill fields, host-fed from
  // `channel` (NOT in momentState). Default empty until channel loads.
  String _title = '';
  String _hostName = '';
  String _shopLogo = '';
  String _shareUrl = '';
  bool _isLive = false; // channel.liveStatus == 1 (host-fed); default VOD.
  // 回放（已結束直播）flag — host-fed (`type == 3 || (type == 2 && liveStatus == 3)`). 與 _isLive
  // 並列、語意分離、互斥。下游 host 讀此把回放渲染成 LIVE 版型 + 「聊天室已關閉」留言態。Default false.
  bool _isFinishedLiveReplay = false;

  bool get isSubscribed => _isSubscribed;
  int get viewerCount => _viewerCount;
  bool get muted => _muted;

  /// LIVE/VOD flag (= `channel.liveStatus == 1`, host-fed). Host gates LIVE vs VOD
  /// chrome on it (LIVE chip / viewer count / 直播限定 chrome). Default `false`.
  bool get isLive => _isLive;

  /// 回放（已結束直播）flag — host-fed (`channel.type == 3 || (type == 2 && liveStatus == 3)`,
  /// via [isFinishedLiveReplay]). 與 [isLive] 並列但語意分離且互斥（`liveStatus` 不可能同時 1 與 3）：
  /// [isLive] 嚴格 `liveStatus == 1`（正在直播），`isFinishedLiveReplay` 標示「回放」。下游（host app
  /// 自組的 reference-ui）讀此把回放渲染成 LIVE 版型 + 「聊天室已關閉」留言態；純 VOD（`type == 1`）
  /// 兩旗標皆 `false` → VOD 版型。Default `false`. parity iOS/Android/RN.
  bool get isFinishedLiveReplay => _isFinishedLiveReplay;

  /// Host-pill title (= `channel.title`). Empty until channel loads (D3).
  String get title => _title;

  /// Host-pill host / shop name (= `channel.shop.name`).
  String get hostName => _hostName;

  /// Host-pill shop logo URL (= `channel.shop.logo`).
  String get shopLogo => _shopLogo;

  /// Share context URL (= `channel.share_url`).
  String get shareUrl => _shareUrl;

  /// Echo the subscribe state (host calls after subscribe success /
  /// `channel.shop.is_subscribe`). Notifies only on change.
  @internal
  void setSubscribed(bool value) {
    if (value == _isSubscribed) return;
    _isSubscribed = value;
    notifyListeners();
  }

  /// Feed the top-bar chrome fields from `channel` (player-chrome-template D3).
  /// Notifies only when at least one field actually changed (one channel-load →
  /// one notify).
  @internal
  void setChrome({
    required String title,
    required String hostName,
    required String shopLogo,
    required String shareUrl,
    bool isLive = false,
    // 回放（已結束直播）flag — host-fed (`type == 3 || (type == 2 && liveStatus == 3)`,
    // via `isFinishedLiveReplay()`). 與 isLive 並列、語意分離、互斥。Default false（源碼相容）。
    bool isFinishedLiveReplay = false,
  }) {
    if (title == _title &&
        hostName == _hostName &&
        shopLogo == _shopLogo &&
        shareUrl == _shareUrl &&
        isLive == _isLive &&
        isFinishedLiveReplay == _isFinishedLiveReplay) {
      return;
    }
    _title = title;
    _hostName = hostName;
    _shopLogo = shopLogo;
    _shareUrl = shareUrl;
    _isLive = isLive;
    _isFinishedLiveReplay = isFinishedLiveReplay;
    notifyListeners();
  }

  /// Echo the running viewer count (`pv_num`). Notifies only on change.
  @internal
  void setViewerCount(int value) {
    if (value == _viewerCount) return;
    _viewerCount = value;
    notifyListeners();
  }

  /// Echo the player mute flag (host calls alongside `controller.setMuted`).
  /// Notifies only on change.
  @internal
  void setMuted(bool value) {
    if (value == _muted) return;
    _muted = value;
    notifyListeners();
  }
}

// ── 5. SubtitleTrack ─────────────────────────────────────────────────────────

/// SubtitleTrack view-model: `{ available, enabled }` (from `is_subtitle` +
/// the current toggle state). Diff-notifies on a real change.
class DefaultSubtitleState extends ChangeNotifier {
  bool _available = false;
  bool _enabled = false;
  String _url = '';

  /// Whether subtitles exist for this video (`is_subtitle`).
  bool get available => _available;

  /// Whether subtitles are currently toggled on (`SubtitleTrack.setEnabled`).
  bool get enabled => _enabled;

  /// The per-channel VTT subtitle URL (`channel.subtitle_url`), raw
  /// passthrough — parsing the VTT itself is reference-ui's job (parity iOS
  /// `rb-ios-subtitle-vtt-caption-display`). Defaults `''` (parity
  /// `LBSubtitleInfo`'s own tolerant-decode default) — flutter-subtitle
  /// -template-wiring.
  String get url => _url;

  /// Echo subtitle availability + toggle state (+ OPTIONAL `url`, flutter
  /// -subtitle-template-wiring). `url` is OPTIONAL and, when omitted,
  /// PRESERVES the current value — every pre-existing 2-arg call site
  /// (`available`/`enabled` only) is source-compatible and unaffected.
  /// Notifies only when at least one field actually changed.
  @internal
  void setAvailability({
    required bool available,
    required bool enabled,
    String? url,
  }) {
    final effectiveUrl = url ?? _url;
    if (available == _available &&
        enabled == _enabled &&
        effectiveUrl == _url) {
      return;
    }
    _available = available;
    _enabled = enabled;
    _url = effectiveUrl;
    notifyListeners();
  }
}

// ── 7. Navigation (swipe-navigate — 相鄰影片導航 view-model) ───────────────────

/// Read-only navigation view-model: the previous / next adjacent video ids
/// (`channel.prev.first?.id` / `channel.next.first?.id` — `LBNavItem.id`),
/// host-fed via `DefaultPlayerTemplate.handleNavTargets`. Parity with iOS
/// `DefaultPlayerNavigation` / Android `DefaultPlayerNavigation` / RN
/// `DefaultPlayerNavigation`. The Flutter core does NOT bridge `LBChannel` /
/// `LBNavItem` to Dart, so the host resolves the two ids from its own channel
/// and feeds them (exactly like `handleHeaderChrome` / `handleEndScreen`).
///
/// `null` ⇒ no adjacent video in that direction (the template's
/// `navigateToPrev()` / `navigateToNext()` forwarders no-op on `null`).
/// Diff-then-notify: `notifyListeners()` fires EXACTLY ONCE per real change.
class DefaultPlayerNavigation extends ChangeNotifier {
  String? _prevVideoId;
  String? _nextVideoId;

  /// Previous adjacent video id (`channel.prev.first?.id`), or null when none.
  String? get prevVideoId => _prevVideoId;

  /// Next adjacent video id (`channel.next.first?.id`), or null when none.
  String? get nextVideoId => _nextVideoId;

  /// Feed the prev/next ids the host resolved from `channel.prev` / `channel.next`
  /// (host-fed — the core bridges no channel to Dart). Notifies only when either
  /// id actually changed (diff-then-notify).
  @internal
  void setNavTargets({String? prevVideoId, String? nextVideoId}) {
    if (prevVideoId == _prevVideoId && nextVideoId == _nextVideoId) return;
    _prevVideoId = prevVideoId;
    _nextVideoId = nextVideoId;
    notifyListeners();
  }
}

// ── 6. PlaybackProgress (VOD-2 — VOD 播放進度 view-model) ──────────────────────

/// VOD playback-progress view-model: `{ position, duration, isPlaying, isReplay }`
/// (VOD-2, parity iOS `DefaultPlaybackProgressState` / Android `PlaybackProgressModel`).
/// `duration == 0.0` ⇒ live (no scrubbable timeline); `isReplay` = a LIVE stream
/// scrubbed behind the live edge (`live_status == 1` only). Host-fed (bridge —
/// the host echoes the native progress); diff-notifies on a real change.
class DefaultPlaybackProgressState extends ChangeNotifier {
  double _position = 0;
  double _duration = 0;
  bool _isPlaying = false;
  bool _isReplay = false;

  double get position => _position;
  double get duration => _duration;
  bool get isPlaying => _isPlaying;

  /// Whether a LIVE stream is scrubbed behind the live edge — drives the LIVE
  /// bottom bar's "聊天室已關閉" variant.
  bool get isReplay => _isReplay;

  /// Echo a VOD playback-progress snapshot (host-fed). Notifies only on change.
  @internal
  void setProgress({
    required double position,
    required double duration,
    required bool isPlaying,
    required bool isReplay,
  }) {
    if (position == _position &&
        duration == _duration &&
        isPlaying == _isPlaying &&
        isReplay == _isReplay) {
      return;
    }
    _position = position;
    _duration = duration;
    _isPlaying = isPlaying;
    _isReplay = isReplay;
    notifyListeners();
  }
}
