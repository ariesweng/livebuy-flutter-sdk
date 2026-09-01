import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultPlayerTemplate, LBPStartPhase, LBEndHotItem;

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
//   2. EndScreenView    — auto-next countdown ring + watch-next + 熱門推薦
//                          (`LBPEndScreen` + `LBPHotCard`)
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
// NOTE — the END moment's TWO variants: the container shows EndScreenView when
// `countdown != null` (the 倒數 variant). The 熱門 variant (`countdown == null` or
// `next` empty) is governed BY the sub-view itself once shown; this skeleton gates
// EndScreenView on `countdown != null` (the sub-view always accepts `hot` so it can
// render either variant). The start moment never coexists with the end moment (end
// implies the video ended → `startPhase == done`), and error always wins. The
// `buffering` start phase is the one NON-full-bleed case (a lightweight
// over-content indicator that leaves the video visible behind) — that behaviour
// lives INSIDE `StartScreenView` per `phase`, not here.
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
//   • onPickHot    → host → core load(hot.id) (switch to the tapped hot video)
//   • onCancel     → host → dismiss the end screen / stay
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
//       void Function()? onSkip })                 // → host-wired (core skipStart)
//
//     Dispatches by `phase`: `loading` → full-screen brand spinner (static ring /
//     `CircularProgressIndicator`, no random); `buffering` → lightweight
//     OVER-CONTENT indicator (does NOT cover full-screen; video visible behind);
//     `splash` → brand splash + skip pill (「略過片頭」→ onSkip); `done` → renders
//     NOTHING (`SizedBox.shrink()`). `skipSec` (if drawn) is PURELY presentational
//     — it MUST NOT auto-fire skip.
//
//   EndScreenView({
//       required ReferenceUITheme theme,
//       required LBEndCountdown? countdown,        // non-null → 倒數變體
//       required List<LBEndNavItem> next,          // watch-next targets (next[0] = preview)
//       required List<LBEndHotItem> hot,           // 熱門變體 set (FIXED SMALL — plain Row/Column)
//       void Function()? onWatchNext,              // → host-wired
//       void Function(LBEndHotItem item)? onPickHot, // → host-wired
//       void Function()? onCancel })               // → host-wired
//
//     倒數變體 (`countdown != null` && next non-empty): `CustomPaint` ring
//     (progress = `countdown.remain / countdown.total`, centre `remain`) +
//     `next[0]` preview card (`cover` placeholder / `title`) + onWatchNext /
//     onCancel. 熱門變體 (`countdown == null` || next empty): `hot` as `LBPHotCard`s
//     in a PLAIN `Row` / `Column` FIXED SMALL set (first N) + onPickHot.
//     `hot[].duration` is an `int` in SECONDS — the surface formats it to `mm:ss`
//     (e.g. `28` → `"00:28"`).
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

  /// Real-image gate threaded to `EndScreenView` for the recommended / watch-next card
  /// covers (rb-flutter-endscreen-recommended-video-cover). `false` (default, demo /
  /// golden / standalone) → the end-screen cards draw the black placeholder only (no
  /// network). `true` (turnkey container over a real video surface) → real `cover`
  /// images load. Parity iOS / Android / RN. Only the end moment consumes it today.
  final bool live;

  // Host-wired interaction callbacks. The container owns NO core action — each is
  // forwarded to the host (which wires it to the core player exit). All optional;
  // a null callback means an inert CTA. The Model carries NO forwarder for these
  // (moment actions are NOT template methods — mirrors iOS / Android `MomentsModel`).

  /// Start-screen「略過片頭」→ host → core `Player.skipStart()`. This layer NEVER
  /// skips, and `skipSec` (if drawn) MUST NOT auto-fire it.
  final void Function()? onSkip;

  /// End-screen「立即觀看」→ host → core load(next videoId).
  final void Function()? onWatchNext;

  /// End-screen 熱門卡片 tap → host → core load(item.id) (switch to that video).
  final void Function(LBEndHotItem item)? onPickHot;

  /// End-screen「取消」/「換一批」exit → host.
  final void Function()? onCancel;

  /// Error-screen「重試」→ host → core re-load. retry is core's job (auto 3×/3s);
  /// this layer ONLY forwards the CTA tap, NEVER retries / loads itself.
  final void Function()? onRetry;

  /// Error / end-screen「返回」/「關閉」→ host → dismiss the moment / player.
  final void Function()? onDismiss;

  const MomentsOverlayView({
    super.key,
    this.template,
    required this.theme,
    this.live = false,
    this.onSkip,
    this.onWatchNext,
    this.onPickHot,
    this.onCancel,
    this.onRetry,
    this.onDismiss,
  });

  @override
  State<MomentsOverlayView> createState() => _MomentsOverlayViewState();
}

class _MomentsOverlayViewState extends State<MomentsOverlayView> {
  /// Read-only snapshot bridge (re-read inside the ListenableBuilder on notify).
  late MomentsModel _model = MomentsModel(template: widget.template);

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
    if (countdown != null || endScreenVisible) {
      // 2. End moment: countdown != null → 倒數變體 (auto-next → 播下一支 next.first);
      //    countdown == null && endScreenVisible → 無倒數「直播已結束」變體（直播結束且無 next：
      //    有 hot 顯示熱門、否則只有標題，end-screen-no-countdown）。`liveEnded` gate 標題。
      //    An upcoming (awaitingLive) channel has countdown == null AND endScreenVisible == false
      //    AND startPhase done → falls through to the PlayerShell upcoming chrome.
      return EndScreenView(
        theme: theme,
        countdown: countdown,
        next: m.next,
        hot: m.hot,
        liveEnded: endScreenVisible && countdown == null,
        // Real cover images on the recommended / watch-next cards at runtime; the
        // black placeholder only at demo / golden (live == false). Threaded from the
        // turnkey container (rb-flutter-endscreen-recommended-video-cover).
        live: widget.live,
        onWatchNext: _handleWatchNext,
        onPickHot: _handlePickHot,
        onCancel: _handleCancel,
      );
    }
    if (m.startPhase != LBPStartPhase.done) {
      // 3. Start splash lifecycle (loading / buffering / splash). `done` falls
      //    through to nothing (the sub-view itself also renders nothing on done).
      return StartScreenView(
        theme: theme,
        phase: m.startPhase,
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

  /// Forward a 熱門卡片 tap → host (→ core load(item.id)).
  void _handlePickHot(LBEndHotItem item) => widget.onPickHot?.call(item);

  /// Forward「取消」/「換一批」→ host.
  void _handleCancel() => widget.onCancel?.call();

  /// Forward「重試」→ host (→ core re-load). retry is core's job (auto 3×/3s); this
  /// layer ONLY forwards the CTA, NEVER retries / loads itself.
  void _handleRetry() => widget.onRetry?.call();

  /// Forward「返回」/「關閉」/「前往更新」→ host (→ dismiss the moment / player).
  void _handleDismiss() => widget.onDismiss?.call();
}
