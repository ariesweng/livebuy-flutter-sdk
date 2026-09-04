// LivebuyLiveEntry — turnkey drop-in「現正直播」floating-entry container (Tier B,
// Flutter parity of iOS / Android / RN introduce-dropin-live-entry-container).
//
// 「全店現正有直播時，畫面角落浮一張入口卡，點了開播放器」是直播導流的主入口。SDK 從未把它
// 做成 drop-in：a host had to own a 30s `LivebuySDK.fetchLatestLive` poll, gate
// `liveStatus == 1`, assemble the bare `FloatingWidgetView`, and wire dismiss / `live_end`
// immediate-hide / drag clamp itself. That logic was re-authored in `flutter/example`
// (`_pollLatestLive` + `_applyLive` + `onPanUpdate` + a `pollReceived` listener).
//
// `LivebuyLiveEntry` PROMOTES it into the package, mirroring the existing `LivebuyWidget` /
// `LivebuyPlayer` containers ("PROMOTE the Example controller → one-line drop-in"):
//
//     Stack(children: [
//       YourHomeContent(),
//       LivebuyLiveEntry(shopId: 'Pw8PJ99J'),                 // all defaults
//       // or with config:
//       LivebuyLiveEntry(shopId: 'Pw8PJ99J', config: cfg),
//     ])
//
// It is an OVERLAY drop-in: place it as a direct child of a `Stack`; its visible state
// builds a corner-anchored `Positioned`, its hidden state a `SizedBox.shrink()`.
//
// floating_setting (rb-flutter-floating-entry-position-timing): the resting corner and the
// appearance timing are driven by three host-injected RAW wire values — `config.position`
// (`left_bottom` / `right_bottom`), `config.timing` (`immediate` / `delay`) and
// `config.delaySeconds`. The host reads them out of `sdkConfig.extensions['floating_setting']`;
// this container NEVER reads `extensions` itself and never interprets backend semantics. All
// three settings apply in BOTH `draggable` modes: the two render branches each already return a
// `Positioned` carrying explicit `right` + `bottom`, so switching corner is a named-argument
// swap — no extra widget node, no layout change. ⚠️ Flutter-specific: the drag offset is folded
// straight INTO the `Positioned` edge value (not a transform layer), so the offset's SIGN FLIPS
// when the corner changes — that derivation lives in ONE place,
// `lbLiveEntryEdgeInset` (`live_entry_position_timing.dart`). Omitting all three keeps the
// container byte-identical to its pre-setting behaviour (bottom-right, immediate, no animation).
//
// Difference vs `LivebuyWidget` (avoid confusion): `LivebuyWidget` = a shop's live LIST
// (carousel / grid); `LivebuyLiveEntry` = a SINGLE auto-detected「現正直播」entry card —
// the host names no video; the container polls `fetchLatestLive` for the current
// `liveStatus == 1` session.
//
// close-grace (rb-flutter-live-entry-close-grace-period): a host mounts this container only while
// `CollapsibleLivebuyPlayer` is NOT showing a video (host-owned `sessionVideo == null` gate), so
// closing that sibling container and mounting this one happen almost back-to-back — which used to
// make this card reappear in the SAME corner almost instantly after the user closed the player,
// even on the common `immediate` `floating_setting`. A fixed, SDK-internal, merchant-config-
// independent 2s buffer (`kLiveEntryCloseGraceMs`, `live_entry_close_gate.dart`) is folded into
// the appearance-timing decision via `math.max(configured floating_setting delay, close-grace
// remaining)` — see `_effectiveAppearDelayMs` / `_reconcileAppearance`. A cold open (the player has
// never been closed this process) always yields `0` close-grace remaining, so this is a
// zero-side-effect addition whenever there is no recent close.
//
// Platform divergence (vs iOS): live-end immediate-hide rides a host-provided
// `config.liveEndedSignal` (`Stream<void>`) rather than an ambient bus — Flutter's core
// event listener is a SINGLE interceptor the host owns (returning `LBEventReply`), so the
// host pumps the signal from its own `pollReceived` + `live_end == 1` handling. Absent the
// signal, the 30s poll + `liveStatus == 1` gate still absorbs an ended live within one
// interval.
//
// PURE ASSEMBLY (governance): pixels reuse the existing `FloatingWidgetView` surface; the
// drag clamp reuses the existing pure `clampFloatingOffset`; the state machine is the
// immutable `LiveEntryState` + pure transitions below. This container adds NO new pixel
// surface, NO view-model, and touches NO template / core / example. One-way dependency
// `reference-ui → template → core` intact.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart'
    show LBVideoItem, LivebuySDK, SDKConfig;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show LBUIOptions;

import '../reference_ui_theme.dart';
import '../widget/external_live.dart' show externalLiveAwareTap;
import '../widget/floating_widget.dart';
import 'collapsible_live_buy_player.dart' show clampFloatingOffset;
import 'live_buy_player.dart' show LivebuyPlayer, LivebuyPlayerConfig;
import 'live_entry_close_gate.dart'
    show LiveEntryCloseGate, liveEntryCloseGraceRemainingMs, msSinceLastPlayerClose;
import 'live_entry_dismiss_memory.dart'
    show LiveEntryDismissMemory, liveEntryInitialDismissedForId;
import 'live_entry_position_timing.dart';
import 'widget_data.dart' show lbWidgetEffectiveTap;

// ─────────────────────────────────────────────────────────────────────────────
// Pure predicates (parity iOS lbLiveEntry* / Android lbLiveEntry* / RN liveEntry*)
// ─────────────────────────────────────────────────────────────────────────────

/// Gate: a `fetchLatestLive` result counts as「現正直播」ONLY when `liveStatus == 1`.
/// Absorbs `null`, `liveStatus == 3` (external-platform live, e.g. Facebook), and a
/// `ty:"live"` VOD fallback (`liveStatus != 1`) → all return `null`. Pure.
LBVideoItem? liveEntryGate(LBVideoItem? video) =>
    (video != null && video.liveStatus == 1) ? video : null;

/// New-live reset predicate: a new session (`newId` differs from the current `currentId`,
/// including `null → id`) returns true so the container resets the user's `dismissed`
/// (closing one live never hides the next). Pure.
bool liveEntryShouldResetDismiss(String? currentId, String? newId) =>
    currentId != newId;

// ─────────────────────────────────────────────────────────────────────────────
// Immutable state machine (parity iOS / Android controller / RN reducer)
// ─────────────────────────────────────────────────────────────────────────────

/// The「現正直播」entry state. Immutable — every transition returns a new value.
@immutable
class LiveEntryState {
  /// The ongoing live to preview, or `null` (no live / gated out / ended).
  final LBVideoItem? live;

  /// Whether the user closed the entry for the CURRENT live (reset on a new live id — see
  /// [liveEntryShouldResetDismiss]). As of `rb-flutter-live-entry-dismiss-survives-remount`, a reset's
  /// new value is decided by [liveEntryInitialDismissedForId], which may seed straight back to `true`
  /// if this live's id matches the last live the user explicitly dismissed (recorded in
  /// [LiveEntryDismissMemory], which survives this container being unmounted and remounted for the
  /// same live) — not always a bare `false` reset.
  final bool dismissed;

  /// The id of the live last applied — detects "new live" to reset `dismissed`.
  final String? lastLiveId;

  /// Live ids reported ENDED — treated as "no live" by [applyLiveEntry] (backend-lag guard).
  final Set<String> endedLiveIds;

  const LiveEntryState({
    this.live,
    this.dismissed = false,
    this.lastLiveId,
    this.endedLiveIds = const <String>{},
  });
}

/// The initial (no-live, not-dismissed) state.
const LiveEntryState initialLiveEntryState = LiveEntryState();

/// Apply an already-GATED result (or `null`). A live whose id was already reported ENDED is
/// treated as "no live" (avoids resurfacing a just-ended live on a stale fetch); on a
/// live-`id` change reset `dismissed` and update `lastLiveId`; finally update `live`.
/// Transition order mirrors iOS / Android `apply` + the example `_applyLive`.
///
/// [lastDismissedId] (rb-flutter-live-entry-dismiss-survives-remount) SHOULD be
/// `LiveEntryDismissMemory.instance.lastDismissedId` — the id of the live the user last explicitly
/// closed via the close button, which may survive a fresh mount of this container (a different
/// `LivebuyLiveEntry` element instance than the one that recorded it). Defaults to `null` (no
/// memory), so existing callers/tests that don't pass it keep the pre-existing "a reset always
/// starts visible" behaviour byte-identical. The reset value itself is decided by the pure
/// [liveEntryInitialDismissedForId] — this function stays purely a function of its explicit inputs;
/// reading the shared singleton is the caller's job (see `_pollLatestLive()`), same division as
/// `_closeGraceRemainingMs()` does for `LiveEntryCloseGate`.
LiveEntryState applyLiveEntry(
  LiveEntryState state,
  LBVideoItem? gated, {
  String? lastDismissedId,
}) {
  var next = gated;
  if (next != null && state.endedLiveIds.contains(next.id)) {
    next = null; // ended → never resurface
  }
  final newId = next?.id;
  if (liveEntryShouldResetDismiss(state.lastLiveId, newId)) {
    return LiveEntryState(
      live: next,
      dismissed: liveEntryInitialDismissedForId(
        newId: newId,
        lastDismissedId: lastDismissedId,
      ),
      lastLiveId: newId,
      endedLiveIds: state.endedLiveIds,
    );
  }
  return LiveEntryState(
    live: next,
    dismissed: state.dismissed,
    lastLiveId: state.lastLiveId,
    endedLiveIds: state.endedLiveIds,
  );
}

/// The shown live has ENDED (host signalled via `liveEndedSignal`). If the currently-shown
/// entry is a live (`liveStatus == 1`), hide it IMMEDIATELY (don't wait for the next poll)
/// and remember its id so a stale fetch cannot resurface it. No-op when not currently
/// showing a live. Parity iOS / Android `handleLiveEnded` / RN `liveEntryHandleEnded`.
LiveEntryState liveEntryHandleEnded(LiveEntryState state) {
  final live = state.live;
  if (live == null || live.liveStatus != 1) return state;
  return LiveEntryState(
    live: null,
    dismissed: state.dismissed,
    lastLiveId: null,
    endedLiveIds: <String>{...state.endedLiveIds, live.id},
  );
}

/// Record the user closing the entry for the current live. Pure — does NOT touch
/// `LiveEntryDismissMemory` itself; that impure write (`recordDismissed`, so the dismissal survives
/// a fresh container mount) happens at the call site, `_dismiss()`, alongside this transition — see
/// `rb-flutter-live-entry-dismiss-survives-remount`.
LiveEntryState liveEntryDismiss(LiveEntryState state) => LiveEntryState(
      live: state.live,
      dismissed: true,
      lastLiveId: state.lastLiveId,
      endedLiveIds: state.endedLiveIds,
    );

// ─────────────────────────────────────────────────────────────────────────────
// Config
// ─────────────────────────────────────────────────────────────────────────────

/// Per-instance wiring for [LivebuyLiveEntry]. All fields optional; each has a documented
/// built-in default. Mirrors the iOS `LivebuyLiveEntryConfig` / Android / RN configs.
class LivebuyLiveEntryConfig {
  /// The merchant SDKConfig used to resolve the theme. Omitted → the container fetches it
  /// via `LivebuySDK.getSdkConfig()` (falling back to `SDKConfig.fallback` if not yet
  /// configured). Provide it to skip the async fetch (e.g. tests).
  final SDKConfig? sdkConfig;

  /// Host UI options forwarded into the theme resolver. Default: none.
  final LBUIOptions? hostOptions;

  /// Whole-entry tap. Default: `null` → the container DEFAULT-opens a full-screen in-app
  /// `LivebuyPlayer` via `Navigator.push` (dropin-live-entry-default-open-player-flutter, mirrors
  /// `LivebuyWidget`). A host wires this to fully override (the default route then never opens);
  /// `onTapVideo: (_) {}` is a true no-op. For an external-platform live
  /// (`externalLiveWatchUrl(item) != null`) the container DEFAULT-opens the platform URL
  /// (`externalLiveAwareTap`, highest precedence); a host wanting to manage external itself wires this.
  final void Function(LBVideoItem item)? onTapVideo;

  /// Close button. Default: `null`. Default behaviour = hide until the「next」live (a new
  /// `video.id` re-surfaces it) — and, as of `rb-flutter-live-entry-dismiss-survives-remount`, this
  /// now genuinely holds even if the host unmounts and later remounts this container for the SAME
  /// live (the common host lifecycle of only mounting `LivebuyLiveEntry` while no player is in the
  /// foreground): the closed live's id is recorded in a small in-memory `LiveEntryDismissMemory`
  /// singleton (`live_entry_dismiss_memory.dart`), NOT persisted to disk, so a process restart
  /// naturally clears it and a host wanting permanent dismissal still records its own flag in
  /// `onClose` and conditionally mounts the container. Only the close button records — tapping the
  /// card to actually watch the live never does.
  final VoidCallback? onClose;

  /// Poll interval. Default: 30s (`fetchLatestLive` failure → 3s fast retry).
  final Duration pollInterval;

  /// Draggable + on-screen clamp. Default: `true` (bottom-right anchored).
  final bool draggable;

  /// Floating window width. Default: `132` — the width of the REUSED `CarouselCardView`
  /// (that card's own design width), NOT the canonical floating component's `96`
  /// (`sdk-components.jsx` 666): this solicitation entry deliberately renders a
  /// title-bearing card instead of the 96-wide pill, and the substitution is recorded in
  /// the spec's carve-out for this surface. Sized through to the reused
  /// `FloatingWidgetView`.
  final double width;

  /// Host-provided「直播已結束」immediate-hide signal (Dart idiomatic `Stream<void>`, parity
  /// Android `Flow<Unit>` / RN subscribe-function / iOS ambient `NotificationCenter`). The
  /// host adds an event from its own `pollReceived` + `live_end == 1` handling. Needed
  /// because Flutter's core event listener is a SINGLE host-owned interceptor (the container
  /// must not steal it). Default: `null` → the 30s poll + `liveStatus == 1` gate still
  /// absorbs an ended live within one interval.
  final Stream<void>? liveEndedSignal;

  /// Resting-corner inset: `dx` = the distance from the OWNED horizontal edge — `right` at the
  /// `right_bottom` [position] (the default), `left` at `left_bottom` — `dy` = bottom. Default
  /// `const Offset(12, 24)` (the prior hardcoded `_inset` value → existing hosts unchanged).
  /// SINGLE source driving BOTH the resting `Positioned` (non-draggable AND draggable) AND the
  /// drag-clamp bound (`clampFloatingOffset` inset), so the resting corner and the drag bound stay
  /// consistent — in BOTH corners. A host with bottom chrome (BottomNavigationBar) sets
  /// `const Offset(12, 70)` to clear it without wrapping its own `Positioned`. Parity iOS
  /// `inset: CGSize` / Android `inset: DpOffset` / RN `inset: { x, y }`.
  final Offset inset;

  // -- floating_setting (rb-flutter-floating-entry-position-timing) ------------
  //
  // 這三個欄位收的是 host 從 `sdkConfig.extensions['floating_setting']` 讀出來的 **raw wire 值**。
  // `extensions` 是 opaque raw bag(`sdk-config` capability 明文規定 SDK 不解讀其語意)，所以容器
  // **不**自己去讀它、**不**解讀後端語意 —— 讀取與注入是 host 責任。`floating_setting` 的
  // `enable`(要不要掛載本容器)與 app scope 四欄 `live` / `video` / `video_source` / `video_id`
  // (選片邏輯)不在本層範圍。全部省略 → 行為與這三個欄位落地前逐字相同。

  /// 初始落點的 raw wire 值(`'left_bottom'` / `'right_bottom'`)。省略 → `null` → 正規化為右下，
  /// 即本欄位落地前 Flutter 的唯一行為。正規化走 `normalizeFloatingPosition`，**嚴格相等**：
  /// `' left_bottom '` / `'LEFT_BOTTOM'` 與任何白名單外字串一律落回右下。
  /// 兩種 [draggable] 模式都生效(兩個 render 分支本來就各自是一個帶顯式 `right` + `bottom` 的
  /// `Positioned`，換邊只換具名參數 → 零新增節點、零版面副作用)。
  final String? position;

  /// 出現時機的 raw wire 值(`'immediate'` / `'delay'`)。省略 → `null` → 正規化為立即，即本欄位
  /// 落地前 Flutter 的唯一行為(無等待、無進場動畫、零額外 widget 節點)。正規化走
  /// `normalizeFloatingTiming`，同一條嚴格相等契約。
  final String? timing;

  /// [timing] 為 `'delay'` 時的等待秒數。預設 [kLiveEntryDefaultDelaySeconds]（`3`，對齊後端
  /// Int-秒欄位 `delay` 自己的預設）。`<= 0` 收斂為零等待。`'immediate'` 時完全無作用。
  /// 欄位名帶 `Seconds` 後綴，以免與同 class 的 [Duration] 型別欄位 [pollInterval] 混淆。
  final int delaySeconds;

  const LivebuyLiveEntryConfig({
    this.sdkConfig,
    this.hostOptions,
    this.onTapVideo,
    this.onClose,
    this.pollInterval = const Duration(seconds: 30),
    this.draggable = true,
    this.width = 132,
    this.liveEndedSignal,
    this.inset = const Offset(12, 24),
    this.position,
    this.timing,
    this.delaySeconds = kLiveEntryDefaultDelaySeconds,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Container
// ─────────────────────────────────────────────────────────────────────────────

/// Turnkey drop-in「現正直播」floating entry. Owns the poll / gate / dismissed / live-end
/// lifecycle; renders NOTHING (`SizedBox.shrink`) when there is no live, it was
/// user-dismissed, or none was detected yet. Pixels reuse [FloatingWidgetView]. Place it as
/// a direct child of a `Stack` (overlay drop-in).
class LivebuyLiveEntry extends StatefulWidget {
  /// Shop ID whose ongoing live is polled (`fetchLatestLive(id = shopId)`).
  final String shopId;

  /// Per-instance wiring (all optional, each defaulted).
  final LivebuyLiveEntryConfig config;

  const LivebuyLiveEntry({
    super.key,
    required this.shopId,
    this.config = const LivebuyLiveEntryConfig(),
  });

  @override
  State<LivebuyLiveEntry> createState() => _LivebuyLiveEntryState();
}

// ⚠️ `TickerProviderStateMixin`，**不是** `SingleTickerProviderStateMixin`。這個 State 在其生命週期
// 內可能建立**不只一個** `Ticker`：host 熱抽換 `config.timing`（`delay → immediate → delay`）時，
// `_applyFloatingSettingUpdate` 會 tear down 舊 controller 再建一個新的。
// `SingleTickerProviderStateMixin.createTicker` 以 `assert(_ticker == null)` 把關，而它的 `_ticker`
// 欄位**從不被重設為 null**（`Ticker.dispose()` 也不回呼 provider），所以第二次建立會在 debug /
// profile 直接拋 “multiple tickers were created”。`immediate` 仍然**一個 Ticker 都不建**
// （`_setUpEntrance` 對非 `delay` early-return），本 mixin 只是允許「一生中先後建立多個」。
class _LivebuyLiveEntryState extends State<LivebuyLiveEntry>
    with TickerProviderStateMixin {
  LiveEntryState _state = initialLiveEntryState;
  late ReferenceUITheme _theme;
  StreamSubscription<void>? _liveEndedSub;

  // Drag state (parity example floating-live-draggable): anchored at the resting corner
  // `_position` (resting committed {0,0}), clamped on-screen via the reference-ui pure
  // `clampFloatingOffset`. The resting inset is `widget.config.inset` (default `Offset(12, 24)`,
  // PROMOTED from the former private `_inset`) — SINGLE source for both the `Positioned` and the
  // clamp, in BOTH corners.
  Offset _drag = Offset.zero;
  Offset _committed = Offset.zero;
  Size _cardSize = Size.zero;

  // -- floating_setting (rb-flutter-floating-entry-position-timing) ------------
  //
  // 兩個 raw wire 值在這裡各自正規化 ONE TIME；下游全部只讀這兩個解析後的值，fallback 不散落。

  /// 解析後的靜止角落。
  late LBFloatingEntryPosition _position;

  /// 解析後的出現時機。
  late LBFloatingEntryTiming _timing;

  /// 出現時機閘。寫入點共 **5** 處（`grep -n "_appeared"` 列舉，rb-flutter-live-entry-close-grace-period
  /// 前是 4 處，見下方 CHANGE HISTORY）：[initState] / [_applyFloatingSettingUpdate] /
  /// [_reconcileAppearance]（`!_eligible` 分支寫 `false`；`immediate` 分支的 `graceMs <= 0` 早返回寫
  /// `true` —— **新增**寫入點，見下）/ [_onAppearTimerFired]。前兩處都走 pure
  /// `lbLiveEntryInitialAppeared(_timing)`，並額外 **AND** 上 `_closeGraceRemainingMs() <= 0`
  /// （**不得**個別拆開重寫成三元運算式）——`delay` 時 `lbLiveEntryInitialAppeared` 已為 `false`，短路、
  /// grace 從不被求值，逐位元不變；`immediate` 時額外要求「當下沒有正在跑的 close-grace」才起始為
  /// `true`，冷開（`LiveEntryCloseGate.instance.lastClosedAtMs == null`）恆滿足、逐位元不變，剛關閉過
  /// 播放器則暫時為 `false`。
  ///
  /// ⚠️ CHANGE HISTORY（rb-flutter-live-entry-close-grace-period）：`_reconcileAppearance()` 原本第一行
  /// 對非 `delay` early-return，使下方兩個寫入點在 `immediate` 路徑上完全不可達——那條 early-return
  /// **已移除**。現在 `immediate` 路徑也會走到 `_reconcileAppearance()`：`!_eligible` 分支可能把
  /// `_appeared` 撥回 `false`（下次變 eligible 時重新求值，含重新讀一次 close-grace），`immediate`
  /// 分支本身在 grace 尚未歸零時會排一個 `Timer`、grace 已歸零時直接同步寫 `true`
  /// （byte-identical 於本 change 之前）。詳細消費鏈見 `lbLiveEntryInitialAppeared` 的 doc（該函式本身
  /// 的角色與契約不變——它仍是「某個 timing enum 該起始成什麼布林」唯一權威，只是呼叫點現在多 AND 一個
  /// 獨立的 grace 條件）與本檔 [_reconcileAppearance] 的 doc。
  late bool _appeared;

  /// `delay` 模式的倒數排程。`null` = 沒有在倒數。
  Timer? _appearTimer;

  /// 進場動畫 controller。**只在 `_timing == delay` 時建立** —— `immediate` 路徑零 `Ticker`、
  /// 零 `Timer`、零額外 widget 節點。
  AnimationController? _entrance;
  CurvedAnimation? _entranceCurved;

  /// 入口「可顯示」：偵測到直播且未被使用者關閉。`delay` 的倒數從這個布林翻成 true 起算
  /// (而不是容器掛載 —— 容器由 host 常駐掛載，見 design D4)。
  bool get _eligible => _state.live != null && !_state.dismissed;

  @override
  void initState() {
    super.initState();
    _position = normalizeFloatingPosition(widget.config.position);
    _timing = normalizeFloatingTiming(widget.config.timing);
    // rb-flutter-live-entry-close-grace-period: AND the per-timing baseline with "no close-grace
    // currently active" — see the `_appeared` field doc above for the full contract.
    _appeared = lbLiveEntryInitialAppeared(_timing) && _closeGraceRemainingMs() <= 0;
    _setUpEntrance();
    // Synchronous fallback theme so build never sees null; refined async from sdkConfig.
    _theme = ReferenceUIThemeResolver.resolve(
      coreTheme: widget.config.sdkConfig?.theme,
      hostOptions: widget.config.hostOptions,
    );
    _resolveTheme();
    _pollLatestLive();
    _subscribeLiveEnded();
  }

  @override
  void didUpdateWidget(covariant LivebuyLiveEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.liveEndedSignal != widget.config.liveEndedSignal) {
      _subscribeLiveEnded();
    }
    _applyFloatingSettingUpdate(oldWidget.config);
  }

  /// Re-resolve the three `floating_setting` seams when the host swaps the config in place.
  /// A `timing` flip rebuilds the entrance controller and re-seeds the appearance gate from the
  /// pure initial-value function (so the new mode starts from ITS baseline, not the old one's).
  void _applyFloatingSettingUpdate(LivebuyLiveEntryConfig old) {
    final nextPosition = normalizeFloatingPosition(widget.config.position);
    final nextTiming = normalizeFloatingTiming(widget.config.timing);
    final timingChanged = nextTiming != _timing;
    final changed = nextPosition != _position ||
        timingChanged ||
        old.delaySeconds != widget.config.delaySeconds;
    if (!changed) return;
    setState(() {
      _position = nextPosition;
      if (timingChanged) {
        _timing = nextTiming;
        _tearDownEntrance();
        _setUpEntrance();
        _cancelAppearTimer();
        // rb-flutter-live-entry-close-grace-period: same AND composition as `initState` above.
        _appeared = lbLiveEntryInitialAppeared(_timing) && _closeGraceRemainingMs() <= 0;
      }
      _reconcileAppearance();
    });
  }

  void _setUpEntrance() {
    if (_timing != LBFloatingEntryTiming.delay) return; // immediate: no Ticker at all
    final controller =
        AnimationController(vsync: this, duration: kLiveEntryEntranceDuration);
    _entrance = controller;
    _entranceCurved =
        CurvedAnimation(parent: controller, curve: kLiveEntryEntranceCurve);
  }

  void _tearDownEntrance() {
    _entranceCurved?.dispose();
    _entranceCurved = null;
    _entrance?.dispose();
    _entrance = null;
  }

  void _cancelAppearTimer() {
    _appearTimer?.cancel();
    _appearTimer = null;
  }

  /// (rb-flutter-live-entry-close-grace-period) Close-grace remaining, in ms, right now — see
  /// `LiveEntryCloseGate` (shared with the fully independent `CollapsibleLivebuyPlayer`) +
  /// `msSinceLastPlayerClose` / `liveEntryCloseGraceRemainingMs` (`live_entry_close_gate.dart`).
  /// `0` for a cold open (`lastClosedAtMs == null`) or once the fixed 2s window has elapsed.
  int _closeGraceRemainingMs() => liveEntryCloseGraceRemainingMs(
        msSinceClose: msSinceLastPlayerClose(
          lastClosedAtMs: LiveEntryCloseGate.instance.lastClosedAtMs,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  /// (rb-flutter-live-entry-close-grace-period) `delay` timing's effective wait: the LONGER
  /// (`math.max` — not additive, not a replacement) of the merchant-configured
  /// `floating_setting` delay (`lbLiveEntryAppearDelay`) and [_closeGraceRemainingMs]. A merchant
  /// `delaySeconds` at or above the fixed 2s grace (the common case) makes this identical to the
  /// pre-existing configured delay — zero new behaviour.
  int _effectiveAppearDelayMs() => math.max(
        lbLiveEntryAppearDelay(_timing, widget.config.delaySeconds).inMilliseconds,
        _closeGraceRemainingMs(),
      );

  /// Reconcile the appearance gate against the current eligibility (and, as of
  /// rb-flutter-live-entry-close-grace-period, the close-grace wait). MUST be called from inside a
  /// `setState` (or from the timer callback, which does its own) — it mutates `_appeared`.
  ///
  /// ⚠️ Runs for BOTH `immediate` and `delay` timing — unlike before this change, which
  /// early-returned on its first line for non-`delay`, making this entire method (and the
  /// `_appeared = true` write in [_onAppearTimerFired] it schedules) unreachable on the `immediate`
  /// path. The close-grace wait can require a genuine wait even on `immediate` (`_close()` /
  /// `onDismiss()` just fired), so that early-return is gone.
  ///
  /// - `delay`: STRUCTURALLY unchanged — a `Timer` is unconditionally scheduled exactly as before
  ///   (even for a `Duration.zero` wait); only the millisecond VALUE now flows through
  ///   [_effectiveAppearDelayMs]'s `math.max`, which collapses to the pre-existing
  ///   `lbLiveEntryAppearDelay` value whenever there is no active close-grace.
  /// - `immediate`: NEW branch. [_closeGraceRemainingMs] `<= 0` (cold open, or the grace already
  ///   elapsed) → synchronous `_appeared = true`, **zero** `Timer` created — byte-identical to this
  ///   change's predecessor behaviour. Otherwise a `Timer` is scheduled for the remaining grace ms
  ///   (never the merchant delay, which is always `0` on `immediate` by definition) — no entrance
  ///   animation plays (`_entrance` stays `null` on `immediate`, per `_setUpEntrance`, untouched by
  ///   this change), the card simply appears once the grace elapses.
  void _reconcileAppearance() {
    if (!_eligible) {
      // 直播結束 / 被關閉 → 作廢排程並讓閘落回，下一場重新求值（含重新讀一次 close-grace）。
      _cancelAppearTimer();
      _appeared = false;
      return;
    }
    if (_appeared || _appearTimer != null) return; // 已顯示 / 已在倒數 → 不重播

    if (_timing != LBFloatingEntryTiming.delay) {
      // immediate (rb-flutter-live-entry-close-grace-period)：只有「剛關閉過播放器」才需要真的等；
      // 冷開 / grace 已過 → 0ms，同步顯示，逐位元對齊本 change 之前的行為。
      final graceMs = _closeGraceRemainingMs();
      if (graceMs <= 0) {
        _appeared = true;
        return;
      }
      _appearTimer = Timer(Duration(milliseconds: graceMs), _onAppearTimerFired);
      return;
    }

    // delay：既有「一律排 Timer」結構不變，秒數改由 `_effectiveAppearDelayMs`
    // （math.max(商家設定, close-grace)）決定 —— 商家 delaySeconds 通常 ≥ 固定 2s grace，此時等同
    // 無新行為。
    _appearTimer = Timer(
      Duration(milliseconds: _effectiveAppearDelayMs()),
      _onAppearTimerFired,
    );
  }

  void _onAppearTimerFired() {
    _appearTimer = null;
    if (!mounted) return;
    setState(() => _appeared = true);
    _entrance?.forward(from: 0);
  }

  @override
  void dispose() {
    _cancelAppearTimer();
    _tearDownEntrance();
    _liveEndedSub?.cancel();
    super.dispose();
  }

  Future<void> _resolveTheme() async {
    final cfg = widget.config.sdkConfig ?? await _safeSdkConfig();
    if (!mounted) return;
    setState(() {
      _theme = ReferenceUIThemeResolver.resolve(
        coreTheme: cfg.theme,
        hostOptions: widget.config.hostOptions,
      );
    });
  }

  Future<SDKConfig> _safeSdkConfig() async {
    try {
      return await LivebuySDK.getSdkConfig();
    } catch (_) {
      return SDKConfig.fallback; // not configured yet — minimal theme
    }
  }

  // live-end immediate hide: subscribe the host signal (parity iOS .lbLiveEnded /
  // Android Flow / RN subscribe-fn). Absent the signal the poll + gate fallback applies.
  void _subscribeLiveEnded() {
    _liveEndedSub?.cancel();
    _liveEndedSub = widget.config.liveEndedSignal?.listen((_) {
      if (!mounted) return;
      _applyState(liveEntryHandleEnded(_state));
    });
  }

  /// THE single state-transition seam. Every transition goes through here so the `delay`
  /// countdown is reconciled against the new eligibility EXACTLY once per transition
  /// (poll / live-end signal / dismiss) — no caller has to remember to do it.
  void _applyState(LiveEntryState next) {
    setState(() {
      _state = next;
      _reconcileAppearance();
    });
  }

  /// Poll loop. `try/catch` (not a swallowed catch) distinguishes "no live" (gated → null
  /// clears the entry) from "request failed / not yet configured" (throw → keep state, 3s
  /// fast retry). Success → steady `pollInterval` cadence. Runs while mounted.
  Future<void> _pollLatestLive() async {
    while (mounted) {
      try {
        final v = await LivebuySDK.fetchLatestLive(widget.shopId);
        if (!mounted) return;
        _applyState(applyLiveEntry(
          _state,
          liveEntryGate(v),
          lastDismissedId: LiveEntryDismissMemory.instance.lastDismissedId,
        ));
        await Future<void>.delayed(widget.config.pollInterval);
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  /// Close-button handler — the ONLY call site that records into `LiveEntryDismissMemory`
  /// (rb-flutter-live-entry-dismiss-survives-remount), so the dismissal survives this container being
  /// unmounted and remounted for the same live. `onTap` / `_openDefaultPlayer` (watching the live) is
  /// a completely separate path and MUST NOT reach this method.
  void _dismiss() {
    final id = _state.live?.id;
    if (id != null) LiveEntryDismissMemory.instance.recordDismissed(id);
    _applyState(liveEntryDismiss(_state));
  }

  /// Default-open player (dropin-live-entry-default-open-player-flutter, mirrors widget): push a
  /// full-screen `LivebuyPlayer` route. `Navigator.push` is a top-level route (independent of this
  /// widget's tree, so a live ending while open does not unmount it) → full-screen regardless of the
  /// entry's small size (design D1). Entry config has no `design` → player uses its default
  /// MinimalDesign; `onDismiss` / `onMinimize` pop the route. Only reached when the host did NOT wire
  /// `config.onTapVideo` (lbWidgetEffectiveTap).
  void _openDefaultPlayer(BuildContext context, LBVideoItem item) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (routeCtx) => LivebuyPlayer(
        videoId: item.id,
        config: LivebuyPlayerConfig(
          onDismiss: () => Navigator.of(routeCtx).pop(),
          onMinimize: () => Navigator.of(routeCtx).pop(),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // dismissed / no live / still inside the `delay` countdown → render NOTHING (parity iOS
    // EmptyView / Android / RN). `_appeared` is permanently `true` on the `immediate` path:
    // every write that CAN run there seeds it from `lbLiveEntryInitialAppeared` (initState and
    // the hot-swap in `_applyFloatingSettingUpdate`), and the two writes that flip it live behind
    // `_reconcileAppearance`'s non-delay early-return. So that path is byte-identical to before.
    // NOTE: do NOT restate this as "nothing rewrites the gate on the immediate path" — a
    // `delay -> immediate` hot swap DOES write it, and must (see the spec's warning on this).
    final live = _state.live;
    if (_state.dismissed || live == null || !_appeared) return const SizedBox.shrink();

    // Reuse the FloatingWidgetView surface. onTap routing (dropin-live-entry-default-open-player-flutter,
    // mirrors widget): external-platform live → open URL (externalLiveAwareTap, highest precedence);
    // non-external → host `onTapVideo` if wired, else the DEFAULT that pushes a full-screen LivebuyPlayer
    // route (lbWidgetEffectiveTap). onClose forwards then marks dismissed.
    final card = FloatingWidgetView(
      theme: _theme,
      liveVideo: live,
      width: widget.config.width,
      live: true,
      onTap: externalLiveAwareTap(
        lbWidgetEffectiveTap(
          widget.config.onTapVideo,
          (item) => _openDefaultPlayer(context, item),
        ),
      ),
      onClose: () {
        widget.config.onClose?.call();
        _dismiss();
      },
    );

    // `delay` only: wrap the CARD (not the positioning `Positioned`) so the scale anchors on the
    // card's own corner, matching the design's `transformOrigin`. `immediate` uses the bare card
    // — ZERO extra widget nodes (design D8).
    final shown = _entranceCurved == null
        ? card
        : _LiveEntryEntrance(
            animation: _entranceCurved!,
            alignment: lbLiveEntryEntranceAlignment(_position),
            child: card,
          );

    final inset = widget.config.inset;

    if (!widget.config.draggable) {
      // 這個分支在 `position` 落地前**就已經**是一個帶顯式 `right` + `bottom` 的 `Positioned`
      // (不是裸卡片)，所以換邊只是換傳哪個具名參數 —— widget 型別不變、節點數不變、在 `Stack`
      // 中的參與方式不變 → `position` 在此模式一樣生效(design D3)。
      final edge = lbLiveEntryEdgeInset(position: _position, inset: inset);
      return Positioned(
        left: edge.left,
        right: edge.right,
        bottom: edge.bottom,
        child: shown,
      );
    }

    // 位移直接算進 `Positioned` 的邊距數值(不是疊 transform)，所以**換邊時正負號會翻**
    // ——右下 `right = inset.dx − off`、左下 `left = inset.dx + off`。該推導只實作在
    // `lbLiveEntryEdgeInset` 一處，兩個分支共用。The pan recognizer only claims an actual drag,
    // so a clean TAP / CLOSE still reaches the FloatingWidgetView.
    final edge = lbLiveEntryEdgeInset(
      position: _position,
      inset: inset,
      offset: _committed + _drag,
    );
    return Positioned(
      left: edge.left,
      right: edge.right,
      bottom: edge.bottom,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _drag += d.delta),
        onPanEnd: (_) => setState(() {
          _committed = clampFloatingOffset(
            committed: _committed,
            translation: _drag,
            cardSize: _cardSize,
            containerSize: MediaQuery.sizeOf(context),
            inset: inset,
            position: _position, // clamp 的可拖曳方向必須跟著錨點換邊
          );
          _drag = Offset.zero;
        }),
        child: _MeasureSize(
          onChange: (s) => _cardSize = s,
          child: shown,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LiveEntryEntrance — 設計稿 `lbp-float-in` 的進場動畫。**只**出現在 `timing == delay` 的路徑上；
// `immediate` 直接用裸卡片(零額外節點)。`Opacity` / `Transform` 都是 paint-only，不影響 layout
// 尺寸，所以外層 `_MeasureSize` 量到的仍是卡片本身的尺寸(拖曳 clamp 不受動畫影響)。
// ─────────────────────────────────────────────────────────────────────────────

class _LiveEntryEntrance extends StatelessWidget {
  /// 已套過 `kLiveEntryEntranceCurve` 的進度(0 → 1)。
  final Animation<double> animation;

  /// 縮放錨點 —— 卡片從所屬角落長出來。
  final Alignment alignment;

  final Widget child;

  const _LiveEntryEntrance({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, inner) {
          final t = animation.value;
          return Opacity(
            opacity: lbLiveEntryEntranceOpacity(t),
            child: Transform.translate(
              offset: Offset(0, lbLiveEntryEntranceTranslateY(t)),
              child: Transform.scale(
                scale: lbLiveEntryEntranceScale(t),
                alignment: alignment,
                child: inner,
              ),
            ),
          );
        },
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _MeasureSize — reports the child's laid-out size (for the drag clamp). Container-local
// equivalent of the example's / CollapsibleLivebuyPlayer's private `_MeasureSize`.
// ─────────────────────────────────────────────────────────────────────────────

class _MeasureSize extends StatefulWidget {
  final ValueChanged<Size> onChange;
  final Widget child;
  const _MeasureSize({required this.onChange, required this.child});

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = context.size;
      if (size != null) widget.onChange(size);
    });
    return widget.child;
  }
}
