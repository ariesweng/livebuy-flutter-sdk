import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultPlayerTemplate, LBPStartPhase, LBEndHotItem;

// rb-flutter-endscreen-live-empty-state: the retired 熱門變體 (為你推薦 grid) is
// gone from `end_screen.dart`'s render (moments.jsx R41). `MomentsOverlayView`'s
// own public `onPickHot` / `MomentsModel.hot` surface is kept UNCHANGED below for
// source-compat across the container chain (`LivebuyPlayerConfig.onPickHot` in
// `live_buy_player.dart` still compiles unmodified) — see the `onPickHot` field's
// own doc comment for why it is currently unread by this container's build.

import '../reference_ui_theme.dart';
import 'moments_model.dart';
// Surface widgets — landed by the parallel Surfaces agents. The container fixes the
// call-site shapes; the file names match the imports EXACTLY (no shim files). Per
// the family file-naming discipline: start_screen.dart (StartScreenView) /
// end_screen.dart (EndScreenView) / error_screen.dart (ErrorScreenView).
import 'start_screen.dart';
import 'end_screen.dart';
import 'error_screen.dart';

// Re-export the three full-screen moment surface widgets so they are publicly
// reachable through the package barrel (`StartScreenView` / `EndScreenView` /
// `ErrorScreenView`), parity with the family-4 export requirement.
export 'start_screen.dart';
export 'end_screen.dart';
export 'error_screen.dart';

// MomentsOverlayView — family-4 player moment container (Flutter SKELETON).
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments, 3 full-screen surfaces).
// Flutter sibling of iOS `MomentsOverlayView.swift` (rb-ios-moments) and Android
// `MomentsOverlayView.kt` (rb-android-moments). (The proposal/tasks call this the
// `MomentsView` role; the type name is `MomentsOverlayView` to read as a full-screen
// overlay composited over the player, mirroring `FeedWinOverlayView` /
// `ProductSheetsOverlayView`. The barrel re-exports it under both intents.)
//
// The top-level family-4 container. It conditionally shows the single ACTIVE
// player-lifecycle moment over the video area — at most ONE moment on screen:
//
//   1. ErrorScreenView  — terminal error screen   (`LBPErrorScreen`)
//   2. EndScreenView    — LIVE-only: auto-next countdown ring + watch-next, OR
//                          (`next` empty)「直播已結束」+ 查看購物車 空狀態
//                          (`LBPEndScreen`, rb-flutter-endscreen-live-empty-state —
//                          the prior 熱門推薦 grid / `LBPHotCard` are RETIRED)
//   3. StartScreenView  — splash lifecycle (loading / buffering / splash)
//                          (`LBPStartScreen`)
//
// ─────────────────────────────────────────────────────────────────────────────
// MOMENT PRIORITY (mutually exclusive — at most ONE moment is shown)
// ─────────────────────────────────────────────────────────────────────────────
//   1. error    != null                       → ErrorScreenView   (HIGHEST)
//   2. else countdown != null                 → EndScreenView     (倒數變體)
//   3. else startPhase != done                → StartScreenView
//   4. else                                   → nothing (stable playback)
//
// NOTE — the END moment's TWO variants (both LIVE-only, rb-flutter-endscreen-live-
// empty-state): the container shows EndScreenView whenever `countdown != null ||
// endScreenVisible` (`endable` below) AND the local 取消 latch hasn't suppressed it
// (`_endScreenDismissed`). WHICH of the two variants (倒數 vs 空狀態) is governed BY
// the sub-view itself from the SAME `countdown` / `next` values — this container
// does not pick a variant. VOD/回放 ending with no `next` never sets
// `endScreenVisible` at all (that sub-state is live-only per `live-end-no-next-
// endstate`), so it never reaches this branch — see `live_buy_player.dart`'s
// `_handleVodEndedDebounce` for how that case closes the player instead. The start
// moment never coexists with the end moment (end implies the video ended →
// `startPhase == done`), and error always wins. The `buffering` start phase is the
// one NON-full-bleed case (a lightweight over-content indicator that leaves the
// video visible behind) — that behaviour lives INSIDE `StartScreenView` per
// `phase`, not here.
//
// ─────────────────────────────────────────────────────────────────────────────
// HOST-WIRED ACTION CALLBACKS (Model is PURE read-only — NO template forwarders)
// ─────────────────────────────────────────────────────────────────────────────
// UNLIKE family-2/3, there is NO public template / player moment INTENT to forward
// to (no `skip` / `retry` / `watchNext` / `pickHot` / `cancel` / `dismiss` on
// `DefaultPlayerTemplate`). So the moment actions are HOST-WIRED CONTAINER
// callbacks — EXACTLY like family-3's `onProductTap` (the open is the host's /
// core's job, not this layer's). The host wires them to the core player exits it
// owns, e.g.:
//   • onSkip       → host → core `Player.skipStart()`
//   • onWatchNext  → host → core load(next videoId) / watch-next exit
//   • onPickHot    → RETIRED (rb-flutter-endscreen-live-empty-state) — kept as a
//                    field for source-compat only, never invoked; see its own doc.
//   • onCancel     → host → typically core `cancelAutoNext()`; this container ALSO
//                    locally closes the whole end-screen overlay (see
//                    `_handleCancel`) — there is no more 熱門 fallback to drop to
//   • onViewCart   → 空狀態「查看購物車」CTA → host (open cart / product list)
//   • onRetry      → host → core re-load (retry is core's job — SDK auto-retries
//                    3×/3s; this layer ONLY forwards the CTA tap, never retries)
//   • onDismiss    → host → dismiss the error / end screen / player
//
// Every callback is null-defaulted, so the container renders correctly action-free
// (demo / golden / widget tests construct it without host wiring); a null callback
// means the corresponding CTA is inert. This layer NEVER calls core skip / retry /
// load itself, and the [MomentsModel] carries NO mutating forwarder (mirrors iOS /
// Android `MomentsModel`, both pure read-only snapshots). Do NOT invent template
// forwarders — none exist for moments.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 3 Surfaces agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
// Every family-4 moment surface widget is a `class … extends StatelessWidget` whose
// constructor takes, IN THIS ORDER (named params — identical convention to
// family-1 / family-2 / family-3):
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. its bound SNAPSHOT VALUE(S)            — read-only state, passed BY VALUE from
//                                                MomentsModel (never the model,
//                                                never the template).
//   3. optional action callbacks             — trailing, EACH defaulting to a
//                                                no-op / null. The container owns NO
//                                                core action; the host wires the
//                                                exits.
//
// A surface widget reads ONLY its passed-in values — it MUST NOT reach back into
// MomentsModel or DefaultPlayerTemplate (one-way data flow), MUST NOT hold a second
// copy of phase / countdown / error, MUST NOT re-classify `LBError` (kind is
// pre-classified by `DefaultErrorState.kindFor`), MUST NOT drive the countdown /
// skip / retry itself (core owns those), MUST render correctly with all callbacks
// null / omitted (so golden / widget tests construct it action-free), and MUST NOT
// use any scrollable container (`ListView` / `GridView` / `SingleChildScrollView`).
// Network images are LIVE-GATED: a moment surface MUST NOT load a network image on
// the golden path (`live == false`) — it draws a deterministic placeholder — and MAY
// overlay the real `cover` only when `live == true` (host runtime) via the shared
// `liveProductImage` loader (rb-flutter-endscreen-recommended-video-cover — the end
// screen's recommended / watch-next cards; cover still image only, no loop preview).
// The auto-next countdown ring is self-drawn with `CustomPaint`; the 熱門 list is a
// PLAIN `Row` / `Column` FIXED SMALL set — NOT a `ListView` / `GridView`.
//
// The three Surfaces agents implement EXACTLY these constructors (see the call sites
// in `build` below):
//
//   StartScreenView({
//       required ReferenceUITheme theme,
//       required LBPStartPhase phase,
//       String coverUrl = '',                      // ← model.loadingCover
//       bool live = false,                          // ← the same `live` prop as EndScreenView
//       void Function()? onSkip })                 // → host-wired (core skipStart)
//
//     Dispatches by `phase`: `loading` → full-screen brand spinner (static ring /
//     `CircularProgressIndicator`, no random) — when `live == true` AND `coverUrl` is
//     non-empty, overlays the real channel cover + a `rgba(0,0,0,0.35)` dark mask
//     under the spinner (player-loading-cover-background-reference-ui-flutter);
//     `buffering` → lightweight OVER-CONTENT indicator (does NOT cover full-screen;
//     video visible behind); `splash` → brand splash + skip pill (「略過片頭」→
//     onSkip); `done` → renders NOTHING (`SizedBox.shrink()`). `skipSec` (if drawn)
//     is PURELY presentational — it MUST NOT auto-fire skip.
//
//   EndScreenView({
//       required ReferenceUITheme theme,
//       required LBEndCountdown? countdown,        // non-null → 倒數變體
//       required List<LBEndNavItem> next,          // watch-next targets (next[0] = preview)
//       void Function()? onWatchNext,              // → host-wired
//       void Function()? onCancel,                 // → host-wired
//       void Function()? onViewCart,               // → host-wired (空狀態 CTA)
//       String liveDuration = '',                  // → 空狀態「直播時長」caption
//       bool live = false })
//
//     倒數變體 (`countdown != null` && next non-empty): `CustomPaint` ring
//     (progress = `countdown.remain / countdown.total`, centre `remain`) +
//     `next[0]` preview card (`cover` placeholder / `title`) + onWatchNext /
//     onCancel. 空狀態 (`countdown == null` || next empty, rb-flutter-endscreen-
//     live-empty-state): a large「直播已結束」title + 「直播時長：…」caption +
//     a full-width「查看購物車」CTA (onViewCart) — NO card wall, NO 熱門
//     recommendations (that grid was retired wholesale by moments.jsx R41).
//
//   ErrorScreenView({
//       required ReferenceUITheme theme,
//       required LBPlayerErrorState error,          // non-null (container gates on non-null)
//       void Function()? onRetry,                   // → host-wired (shown only for stream)
//       void Function()? onDismiss })               // → host-wired
//
//     依 `error.kind` 切換人話文案 (NO raw code): `stream`「播放發生問題」(重試 onRetry
//     + 返回 onDismiss) / `notFound`「找不到影片」(僅 onDismiss, no retry) /
//     `outdated`「請更新版本」(前往更新 / onDismiss, no retry). `phase` is always
//     `failed`. retry is core's job — the CTA only FORWARDS onRetry.
// ─────────────────────────────────────────────────────────────────────────────

/// The family-4 full-screen player moment container. Binds the three template moment
/// `ChangeNotifier`s (`startScreen` + `endScreen` + `errorState`) with
/// `ListenableBuilder`, re-reads the read-only [MomentsModel] on each notify, and
/// shows the single ACTIVE moment (error > end-countdown > start, mutually exclusive)
/// by passing snapshot values BY VALUE to the surface widgets. Paints with the
/// resolved [ReferenceUITheme]. All moment actions are host-wired container callbacks
/// (no template moment intents exist).
///
/// `template == null` → the container uses the deterministic [MomentsSeeds] (no
/// listenables to bind); the host normally supplies a live [DefaultPlayerTemplate].
class MomentsOverlayView extends StatefulWidget {
  /// Live template (host-supplied). `null` → deterministic demo seeds.
  final DefaultPlayerTemplate? template;

  /// Resolved reference-ui theme.
  final ReferenceUITheme theme;

  /// Real-image gate threaded to `EndScreenView` (recommended / watch-next card
  /// covers, rb-flutter-endscreen-recommended-video-cover) AND `StartScreenView`
  /// (`.loading`'s real channel cover background,
  /// player-loading-cover-background-reference-ui-flutter). `false` (default, demo /
  /// golden / standalone) → both surfaces draw their black / solid-brand placeholder
  /// only (no network). `true` (turnkey container over a real video surface) → real
  /// cover images load. Parity iOS / Android / RN.
  final bool live;

  /// 「乾淨模式」snapshot (rb-flutter-clean-mode-upcoming-intro-coverage, Requirement B)
  /// — bubbled from `PlayerShellView`'s own `_cleanMode` gesture state, through the turnkey
  /// container's `PlayerOverlayContext.cleanMode` (`live_buy_player.dart`'s `_cleanMode`,
  /// already the SAME live value `reference_ui_design.dart` forwards to `FeedWinOverlayView`
  /// today), forwarded straight through to `StartScreenView.cleanMode` (see [build]'s
  /// `StartScreenView(...)` call site below) — only meaningful while `phase == .splash`, that
  /// surface ignores it otherwise. `false` (DEFAULT — every EXISTING call site) keeps this
  /// container's composition byte-identical to before this change. This container holds NO
  /// state of its own for it (read-only snapshot, same one-way-data-flow discipline as [live]).
  ///
  /// NOTE — the opening MP4's own playback position/duration (`StartScreenView.introPosition`
  /// / `.introDuration`) are DELIBERATELY NOT threaded here: there is no core-side data pipeline
  /// yet that reports the intro player's own position back up through `MomentsModel` (that
  /// pipeline is a cross-layer, core-touching follow-up — out of scope for a reference-ui-layer
  /// change per OpenSpec's one-layer-per-change rule; see design.md). `StartScreenView` keeps
  /// its `0`/`0` defaults for both, same as every platform's parallel same-batch sibling.
  final bool cleanMode;

  // Host-wired interaction callbacks. The container owns NO core action — each is
  // forwarded to the host (which wires it to the core player exit). All optional;
  // a null callback means an inert CTA. The Model carries NO forwarder for these
  // (moment actions are NOT template methods — mirrors iOS / Android `MomentsModel`).

  /// Start-screen「略過片頭」→ host → core `Player.skipStart()`. This layer NEVER
  /// skips, and `skipSec` (if drawn) MUST NOT auto-fire it.
  final void Function()? onSkip;

  /// End-screen「立即觀看」→ host → core load(next videoId).
  final void Function()? onWatchNext;

  /// rb-flutter-endscreen-live-empty-state: NO LONGER READ by [_buildActiveMoment] —
  /// `end_screen.dart`'s 熱門變體 (為你推薦 grid) that used to invoke this was
  /// removed per the moments.jsx R41 redesign (there is no more hot-card tap to
  /// forward). Kept as a field for source-compat with `LivebuyPlayerConfig.onPickHot`
  /// (`live_buy_player.dart`) — a host that already wires it keeps compiling, the
  /// callback simply never fires any more. A full removal is a documented follow-up.
  final void Function(LBEndHotItem item)? onPickHot;

  /// End-screen 倒數變體「取消」exit → host. The container now ALSO closes the
  /// whole end-screen overlay locally on this tap (rb-flutter-endscreen-live-empty-
  /// state — there is no more 熱門 fallback to drop back to); this callback still
  /// fires alongside that so the host's own core wiring (`cancelAutoNext()`) keeps
  /// stopping the countdown.
  final void Function()? onCancel;

  /// 空狀態「查看購物車」CTA → host. This container applies NO fallback of its own
  /// when null — the OUTER turnkey container (`LivebuyPlayer` in
  /// `live_buy_player.dart`) resolves `config.onViewCart ?? () =>
  /// controller.requestViewCart()` before ever constructing this widget (the SAME
  /// core seam the product list / detail sheet's own cart CTA already uses —
  /// notification-type `VIEW_CART`, `event-interceptor` spec; the template owns no
  /// cart page, the host is the sole handler). A caller that constructs
  /// [MomentsOverlayView] directly (demo / golden / widget tests) simply gets an
  /// inert CTA when this is null.
  final void Function()? onViewCart;

  /// Error-screen「重試」→ host → core re-load. retry is core's job (auto 3×/3s);
  /// this layer ONLY forwards the CTA tap, NEVER retries / loads itself.
  final void Function()? onRetry;

  /// Error / end-screen「返回」/「關閉」→ host → dismiss the moment / player.
  final void Function()? onDismiss;

  /// Clean-mode intro progress bar play/pause tap (rb-flutter-intro-progress-bar-interactive) —
  /// forwarded straight through to `StartScreenView.onTogglePlayPause`. Identical signature to
  /// `PlayerShellView.onTogglePlayPause`; the turnkey container passes the SAME already-resolved
  /// `PlayerOverlayContext.onTogglePlayPause` (`c.onTogglePlayPause`, already defaulted to
  /// `_controller.togglePlayPause` in `live_buy_player.dart`) to both call sites — no new
  /// default-resolution logic. `null` (default) → the bar's play/pause button is inert (demo /
  /// golden / standalone).
  final VoidCallback? onTogglePlayPause;

  /// Clean-mode intro progress bar drag-seek (rb-flutter-intro-progress-bar-interactive) —
  /// forwarded straight through to `StartScreenView.onSeek`. Identical signature to
  /// `PlayerShellView.onSeek`; same reasoning as [onTogglePlayPause] — the SAME already-resolved
  /// `c.onSeek` (defaulted to `_controller.seek`). `null` (default) → the bar's track is
  /// draggable for local visual feedback only, no real seek fires.
  final void Function(double seconds, {double? duration})? onSeek;

  /// 空狀態「直播時長：HH:MM:SS」caption 資料源 (rb-flutter-endscreen-live-duration) — already
  /// FORMATTED (host-fed, mirrors `EndScreenView.liveDuration`'s own contract; source is
  /// `LBPlayerMomentInfo.liveDurationSeconds`, bridged from native `LBPlayerMomentState
  /// .liveDurationSeconds` — see `live_buy_player.dart`'s `formatEndScreenLiveDuration`),
  /// forwarded straight through to `EndScreenView.liveDuration` (see [build]'s `EndScreenView(...)`
  /// call site below) — only meaningful while the 空狀態 (no-countdown) end-screen variant is
  /// shown, that surface's own fallback (`'--:--:--'`) covers the rest. `''` (DEFAULT — every
  /// EXISTING call site) keeps this container's composition byte-identical to before this change.
  /// This container holds NO state of its own for it (read-only pass-through, same one-way-data-
  /// flow discipline as [live]/[cleanMode]).
  final String liveDuration;

  const MomentsOverlayView({
    super.key,
    this.template,
    required this.theme,
    this.live = false,
    this.cleanMode = false,
    this.onSkip,
    this.onWatchNext,
    this.onPickHot,
    this.onCancel,
    this.onViewCart,
    this.onRetry,
    this.onDismiss,
    this.onTogglePlayPause,
    this.onSeek,
    this.liveDuration = '',
  });

  @override
  State<MomentsOverlayView> createState() => _MomentsOverlayViewState();
}

class _MomentsOverlayViewState extends State<MomentsOverlayView> {
  /// Read-only snapshot bridge (re-read inside the ListenableBuilder on notify).
  late MomentsModel _model = MomentsModel(template: widget.template);

  /// rb-flutter-endscreen-live-empty-state: local "the end-screen overlay was
  /// closed by a 取消 tap" latch. `endScreenVisible` stays server/core-driven
  /// (`state == 'endScreenShown'`) and this container never resets it itself, so a
  /// LOCAL suppress-flag is the only way to hide the moment for the REST of this
  /// video's end-state while staying in that state — there is no more 熱門
  /// fallback to drop back to (moments.jsx R41). Reset to `false` on the NEXT
  /// fresh entry into the end state (the rising edge tracked by [_wasEndable]) so
  /// a later, DIFFERENT live-end is unaffected. See [_handleCancel].
  bool _endScreenDismissed = false;

  /// Previous build's "should the end moment be shown at all" (`countdown != null
  /// || endScreenVisible`) — tracked ONLY to detect the false→true rising edge
  /// that resets [_endScreenDismissed] for a fresh end-state entry.
  bool _wasEndable = false;

  @override
  void didUpdateWidget(covariant MomentsOverlayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template) {
      _model = MomentsModel(template: widget.template);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;

    // Bind the three template moment ChangeNotifiers so any change re-reads the
    // model. With no live template (demo seeds) there is nothing to listen to —
    // render the seeds directly.
    final mergeable = <Listenable>[
      if (t != null) ...[
        t.startScreen,
        t.endScreen,
        t.errorState,
        // rb-flutter-intro-progress-bar-interactive: a progress tick during `splash` (the intro
        // MP4's own position/duration/isPlaying, reported by native through the SAME shared
        // `playbackProgress` the VOD progress bar reads — see `MomentsModel.introPosition`'s own
        // doc comment) must re-run `_buildActiveMoment` so the clean-mode progress bar's fill
        // stays live. Was NOT listened to before this change (introPosition/introDuration stayed
        // static `0`/`0`, so there was nothing to react to).
        t.playbackProgress,
      ],
    ];

    if (mergeable.isEmpty) {
      return _buildActiveMoment(context);
    }
    return ListenableBuilder(
      listenable: Listenable.merge(mergeable),
      builder: (context, _) => _buildActiveMoment(context),
    );
  }

  /// The single active moment by priority, or an empty `SizedBox.shrink()` for
  /// stable playback. Mutually exclusive — error wins, then the auto-next countdown
  /// end screen, then the start splash while not `done`.
  Widget _buildActiveMoment(BuildContext context) {
    final theme = widget.theme;
    final m = _model;
    final error = m.error;
    final countdown = m.countdown;

    if (error != null) {
      // 1. Terminal error — HIGHEST priority. The surface takes a non-null error
      //    (the container gates on non-null here).
      return ErrorScreenView(
        theme: theme,
        error: error,
        onRetry: _handleRetry,
        onDismiss: _handleDismiss,
      );
    }
    final endScreenVisible = m.endScreenVisible;
    // rb-flutter-endscreen-live-empty-state: reset the local 取消 suppress-latch on
    // a FRESH entry into the end state (false→true rising edge) — a stale 取消 from
    // a PRIOR live-end MUST NOT swallow a later, different one. Must run BEFORE the
    // gate below reads `_endScreenDismissed`.
    final endable = countdown != null || endScreenVisible;
    if (endable && !_wasEndable) {
      _endScreenDismissed = false;
    }
    _wasEndable = endable;
    if (endable && !_endScreenDismissed) {
      // 2. End moment: countdown != null → 倒數變體 (auto-next → 播下一支 next.first);
      //    countdown == null && endScreenVisible → 空狀態「直播已結束」（直播結束且無
      //    next — 熱門變體已於 moments.jsx R41 移除，rb-flutter-endscreen-live-empty-
      //    state）。An upcoming (awaitingLive) channel has countdown == null AND
      //    endScreenVisible == false AND startPhase done → falls through to the
      //    PlayerShell upcoming chrome. VOD/回放 ended-with-no-next never reaches
      //    here at all (endScreenVisible stays false, live-end-no-next-endstate is
      //    LIVE-only) — the container's own `_handleVodEndedDebounce` (see
      //    `live_buy_player.dart`) closes the player instead of landing on this
      //    branch.
      return EndScreenView(
        theme: theme,
        countdown: countdown,
        next: m.next,
        // Real cover images on the watch-next preview card at runtime; the black
        // placeholder only at demo / golden (live == false). Threaded from the
        // turnkey container (rb-flutter-endscreen-recommended-video-cover).
        live: widget.live,
        onWatchNext: _handleWatchNext,
        onCancel: _handleCancel,
        onViewCart: _handleViewCart,
        // rb-flutter-endscreen-live-duration — direct pass-through, see
        // [MomentsOverlayView.liveDuration]'s own doc comment.
        liveDuration: widget.liveDuration,
      );
    }
    if (m.startPhase != LBPStartPhase.done) {
      // 3. Start splash lifecycle (loading / buffering / splash). `done` falls
      //    through to nothing (the sub-view itself also renders nothing on done).
      return StartScreenView(
        theme: theme,
        phase: m.startPhase,
        // Real cover photo behind `.loading`'s brand-mark animation at runtime; the
        // solid brand backdrop only at demo / golden (live == false). Threaded from
        // the turnkey container — the SAME `live` flag already passed to
        // `EndScreenView` above (player-loading-cover-background-reference-ui-flutter).
        coverUrl: m.loadingCover,
        live: widget.live,
        // rb-flutter-clean-mode-upcoming-intro-coverage — straight pass-through, see
        // [MomentsOverlayView.cleanMode]'s own doc comment.
        cleanMode: widget.cleanMode,
        // rb-flutter-intro-progress-bar-interactive: real intro playback snapshot (supersedes
        // the old always-`0`/`0` defaults) + the host-wired play/pause / seek control plane —
        // see [MomentsModel.introPosition] / [onTogglePlayPause] / [onSeek]'s own doc comments.
        introPosition: m.introPosition,
        introDuration: m.introDuration,
        introIsPlaying: m.introIsPlaying,
        onTogglePlayPause: widget.onTogglePlayPause,
        onSeek: widget.onSeek,
        onSkip: _handleSkip,
      );
    }
    // 4. Stable playback — no moment overlay.
    return const SizedBox.shrink();
  }

  // -- Host-wired action funnels (container owns NO core action) --------------
  //
  // Each forwards to the host callback. The host wires it to the core player exit
  // it owns (skipStart / load(next) / load(hot.id) / re-load / dismiss). reference-ui
  // NEVER calls core skip / retry / load itself; the Model carries NO forwarder.

  /// Forward「略過片頭」→ host (→ core `Player.skipStart()`). This layer NEVER skips.
  void _handleSkip() => widget.onSkip?.call();

  /// Forward「立即觀看」→ host (→ core load(next videoId)).
  void _handleWatchNext() => widget.onWatchNext?.call();

  /// 倒數變體「取消」→ (1) locally close the WHOLE end-screen overlay for the
  /// REST of this video's end state (rb-flutter-endscreen-live-empty-state — see
  /// [_endScreenDismissed]'s doc; the retired 熱門 fallback no longer exists), THEN
  /// (2) forward to host (→ typically core `cancelAutoNext()`, which stops the
  /// countdown). `setState` is REQUIRED here — this widget MUST NOT rely on the
  /// host's `onCancel` side effect (e.g. `endScreen.cancel()`'s own
  /// `notifyListeners()`) to schedule the rebuild that hides the moment: a host
  /// that overrides `onCancel` with unrelated logic (or leaves it null) would
  /// otherwise leave the (now internally dismissed) end screen visibly stuck on
  /// screen. Order matters too: the local dismiss must win even if the host
  /// callback is null / a no-op.
  void _handleCancel() {
    setState(() => _endScreenDismissed = true);
    widget.onCancel?.call();
  }

  /// Forward「查看購物車」→ host. NO local fallback — see [MomentsOverlayView
  /// .onViewCart]'s doc for why the `Player.requestViewCart()` default lives one
  /// layer up (`live_buy_player.dart`'s `LivebuyPlayer`), not here.
  void _handleViewCart() => widget.onViewCart?.call();

  /// Forward「重試」→ host (→ core re-load). retry is core's job (auto 3×/3s); this
  /// layer ONLY forwards the CTA, NEVER retries / loads itself.
  void _handleRetry() => widget.onRetry?.call();

  /// Forward「返回」/「關閉」/「前往更新」→ host (→ dismiss the moment / player).
  void _handleDismiss() => widget.onDismiss?.call();
}
