import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show LBPStartPhase;

import '../playershell/playback_progress_bar_view.dart' show PlaybackProgressBarView;
import '../productsheets/sheet_scaffold.dart' show liveProductImage;
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'chevron_forward_glyph.dart';
import 'loading_mark_animation_view.dart';

// StartScreenView — family-4 moments surface 1 (start-lifecycle).
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments, surface 1).
// Design: `design/templates/minimal/moments.jsx` start components (design re-sync
//   `LL9WzHAq`): `LBPLoadingOverlay` (`loading`) / `LBPBufferingSpinner` (`buffering`)
//   / `LBPSkipIntroButton` (`splash`).
// Parity: iOS `StartScreenView.swift` + Android `StartScreenView.kt`
//   (rb-flutter-splash-skip-only — splash redesigned to a lightweight skip-only
//   overlay). Golden parity name: `start-screen-splash-default`.
//
// This is family-4 SURFACE 1. It implements the documented SUB-VIEW INPUT PATTERN
// from `moments_view.dart` EXACTLY (identical convention to family-1/2/3):
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. its bound SNAPSHOT VALUE(S)             — `phase: LBPStartPhase`, the
//      read-only mirror of `DefaultStartScreenState.phase`, passed BY VALUE from
//      `MomentsModel.startPhase` (never the model, never the template); plus
//      `coverUrl: String` / `live: bool` (player-loading-cover-background-
//      reference-ui-flutter), `.loading`'s optional real-cover overlay inputs —
//      see [resolveLoadingCoverUrl] — both default-safe (`''` / `false`).
//   3. one optional action callback, trailing, defaulting to `null` (`onSkip`).
//      The container / host wires it to the core player exit (`skipStart()`); this
//      surface does NOT own the skip intent and renders correctly with it null (so
//      demo / golden / widget tests construct it action-free).
//
// One-way data flow: this view reads ONLY its passed-in `phase` (+ `coverUrl` /
// `live`) — it never reaches back into `MomentsModel` or `DefaultPlayerTemplate`,
// never holds a second copy of the phase, and NEVER drives the skip itself. The
// splash skip pill shows a STATIC「略過介紹」label (rb-ios-skip-intro-label-static —
// no `(N)` countdown). The host wires `onSkip` to core `skipStart()`; this layer
// only FORWARDS the CTA tap.
//
// Phase dispatch (mirrors the moments.jsx start components):
//   • `loading`   → full-bleed brand background + centered 17-frame PNG-sequence
//                   brand-mark animation (`LoadingMarkAnimationView`,
//                   rb-flutter-loading-mark-png-sequence, parity iOS/Android) ONLY
//                   — NO wordmark / 「載入中…」caption (rb-flutter-loading-announce-
//                   restyle, design re-sync `c3c98733`: `LBPLoadingOverlay` dropped
//                   both).
//   • `buffering` → renders NOTHING (`SizedBox.shrink()`).
//   • `splash`    → the opening video plays through the NORMAL path with the subject
//                   chrome (LIVE / VOD) visible behind; the ONLY added UI is a
//                   bottom-right「略過介紹」skip pill. NO 片頭 tag / muted indicator /
//                   brand backdrop / lower-third title card / progress bar (all
//                   removed — 開場影片有聲、不接管畫面). `cleanMode == true`
//                   (rb-flutter-clean-mode-upcoming-intro-coverage, ADDED — no design.jsx
//                   counterpart) flips this: the skip pill hides and an expanded, FULLY
//                   INTERACTIVE progress bar (rb-flutter-intro-progress-bar-interactive —
//                   supersedes the original read-only version; pause/resume + drag-seek,
//                   bound to the intro's OWN `introPosition`/`introDuration`/`introIsPlaying`)
//                   shows instead — see [StartScreenView.cleanMode]'s own doc comment,
//                   including its SCOPE NOTE on end-to-end wiring.
//   • `done`      → renders NOTHING (`SizedBox.shrink()`).
//
// RENDERING GOTCHAS (inherited from family-1/2/3 / iOS / Android): plain Column /
// Row / Stack only — NO scrollable container (`ListView` / `GridView` /
// `SingleChildScrollView`) and NO network image (`Image.network` / `NetworkImage`).
// Glyphs are `Icons.*`. No randomness.
//
// `.loading`'s brand-mark is the ONE narrow, spec-documented exception to the
// "no animation" golden-determinism rule (rb-flutter-loading-mark-png-sequence):
// `LoadingMarkAnimationView` plays a 17-frame PNG sequence via `Timer.periodic`
// (see its own file doc for the full rationale + probe-test evidence). This does
// NOT loosen the rule for anything else in this file. The former static
// `_spinnerRing()` / `_SpinnerRingPainter` (CustomPaint, no animation, byte-stable)
// that `.loading` used to call are REMOVED — `flutter analyze` flags fully unused
// private declarations as a warning, so once `.loading` stopped calling them they
// were dead code with no reason to keep (unlike iOS/Android, where the analogous
// leftover procedural spinner is a lower-severity/no-op finding and was left in
// place — see design.md Risks). A golden test that renders `.loading` WITHOUT an
// extra `tester.pump(duration)` / `pumpAndSettle()` after `pumpWidget` still
// deterministically captures frame 0 — `Timer.periodic` needs the virtual clock
// actively advanced to tick at all.
//
// NETWORK-URI IMAGE EXCEPTION (`.loading` cover ONLY, player-loading-cover-
// background-reference-ui-flutter): the "no network image" rule above carries a
// SECOND narrowly-scoped carve-out, alongside `.loading`'s brand-mark animation
// exception. When a real turnkey container passes `live: true` AND a non-empty
// `coverUrl` (gated by the pure [resolveLoadingCoverUrl] below), `.loading`'s
// background overlays the channel's real cover photo (+ a `rgba(0,0,0,0.35)` dark
// mask) via the SAME shared, already-approved `liveProductImage` loader the
// family-4 sibling `EndScreenView` already uses for its recommended / watch-next
// cover cards (`../productsheets/sheet_scaffold.dart`) — NOT a new
// `Image.network` / `NetworkImage` call site of its own. `live` defaults to
// `false` and `coverUrl` defaults to `''` at every existing call site (demo /
// golden / widget tests all omit both), so this branch is dead there and the
// pre-existing solid-brand-backdrop rendering stays byte-identical — no baseline
// needs regenerating.

// MARK: - Fixed decorative design tokens (literal minimal hex via colorFromHex)

/// Loading brand backdrop (`background: '#0C0C10'`).
final Color _brandBackdrop = colorFromHex('#0C0C10') ?? const Color(0xFF0C0C10);

/// Chrome capsule fill (`rgba(20,20,24,…)`).
final Color _chromeFill = colorFromHex('#141418') ?? const Color(0xFF141418);

// MARK: - Fixed localized copy (static presentation strings — parity to iOS/Android)

// rb-ios-skip-intro-label-static (four-platform parity): the skip pill shows a STATIC
// 「略過介紹」label with NO `(N)` countdown (the host wires `onSkip` → core `skipStart()`).
const String _skipLabel = '略過介紹';

// MARK: - Loading cover gate (pure, directly unit-testable)

/// Decide whether the `.loading` background should draw the channel's real cover
/// photo (+ dark mask) or fall back to the solid brand backdrop. Parity iOS
/// `loadingCoverURL(live:coverUrl:)` / RN `resolveLoadingCoverUri`
/// (`player-loading-cover-background-reference-ui-rn`) / this file family's own
/// `resolveShopLogoUrl` (`video_info_panel.dart` / `player_header_bar_view.dart`)
/// ladder discipline:
///   Rung 1 — [live] is not `true` (demo / golden / preview) → `null` (solid
///            backdrop; [urlString] is irrelevant, never inspected).
///   Rung 2 — [urlString] is `null` / empty / whitespace-only after trim → `null`
///            (solid backdrop).
///   Rung 3 — otherwise the TRIMMED url string.
///
/// The draw site MUST express "do we overlay a cover?" as
/// `resolveLoadingCoverUrl(...) != null` and MUST NOT re-derive an equivalent test
/// (`live && coverUrl.trim().isNotEmpty` and friends) — same discipline note as
/// `resolveShopLogoUrl`: the moment the decision and the drawing are implemented
/// separately they drift.
///
/// Pure: no I/O, no global state, no mutation, no widget types. Safe to call per-build.
String? resolveLoadingCoverUrl({required bool live, required String? urlString}) {
  // Rung 1 — the runtime image gate is closed (demo / golden / preview).
  if (!live) return null;
  // Rung 2 — nothing usable to load (null / empty / whitespace-only).
  final trimmed = urlString?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  // Rung 3 — load the trimmed URL.
  return trimmed;
}

// MARK: - Clean-mode splash progress bar bottom inset (pure)

/// PURE: the `splash` phase's clean-mode progress-bar bottom inset
/// (rb-flutter-clean-mode-upcoming-intro-coverage). A deliberate DUPLICATE of
/// `player_shell_view.dart`'s `progressBarBottomSafeAreaInset` formula (same design source,
/// `screens.jsx:420-424`'s `Math.max(0, safeArea.bottom - (platform==='android'?8:0))`) rather
/// than an import of that family-1 file — this file (family-4 moments) has no existing dependency
/// on `playershell/player_shell_view.dart` and this is a 2-line formula, not a stateful component;
/// duplicating it here keeps the two families' implementation files independent, the same
/// discipline this package already applies across iOS/Android/RN platform boundaries for
/// formulas like [resolveLoadingCoverUrl]'s own design-parity siblings. A DIFFERENT drift here
/// would only ever affect the visual bottom offset of one non-interactive bar — low blast radius —
/// and any future divergence is easy to catch by diffing the two doc comments. Unit-testable
/// without a widget.
double splashProgressBarBottomInset(double safeAreaBottom, {required bool isAndroid}) {
  final adjusted = safeAreaBottom - (isAndroid ? 8.0 : 0.0);
  return adjusted < 0 ? 0 : adjusted;
}

/// The family-4 start-lifecycle surface. Dispatches by [phase]: a full-screen brand
/// loader (`loading`), nothing (`buffering`), a lightweight bottom-right skip pill over
/// the playing opening video (`splash`), or nothing (`done`). Read-only — it never skips
/// itself; the skip pill only FORWARDS [onSkip] (the host wires it to core `skipStart()`).
class StartScreenView extends StatelessWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// The start lifecycle phase (`DefaultStartScreenState.phase`), passed BY VALUE
  /// from `MomentsModel.startPhase`. Drives which branch renders. Read-only.
  final LBPStartPhase phase;

  /// The channel's GENERAL (non-upcoming-scoped) `.loading`-phase cover photo,
  /// passed BY VALUE from `MomentsModel.loadingCover` (never the model/template).
  /// Empty string (default) → `.loading` draws the solid brand backdrop only.
  /// Ignored unless [live] is also `true` — see [resolveLoadingCoverUrl].
  final String coverUrl;

  /// Real-image gate — `false` (default; demo / golden / standalone) → `.loading`
  /// draws the solid brand backdrop only (no network). `true` (turnkey container
  /// over a real video surface) → `.loading` overlays the real [coverUrl] + a dark
  /// mask. Parity iOS `live` / Android `context.live` / RN `live` — the SAME
  /// container flag already threaded to the sibling `EndScreenView(live: ...)`
  /// (`moments_view.dart`).
  final bool live;

  /// 「乾淨模式」snapshot (rb-flutter-clean-mode-upcoming-intro-coverage, Requirement B —
  /// ADDED capability, no design.jsx counterpart: design's own `moments.jsx` splash component
  /// carries no clean-mode concept at all, this is a Flutter-reference-ui EXTENSION, parity to
  /// the sibling iOS/Android/RN changes landing the same behaviour in the same batch). Only
  /// meaningful during [LBPStartPhase.splash] — the `loading` / `buffering` / `done` branches
  /// ignore it entirely. `false` (DEFAULT — every EXISTING call site) keeps the `splash` branch
  /// byte-identical to before this change: skip pill shown, no progress bar. `true` hides the
  /// skip pill and shows a **fully interactive** expanded progress bar
  /// (rb-flutter-intro-progress-bar-interactive — supersedes the prior read-only version) bound
  /// to [introPosition] / [introDuration] / [introIsPlaying], reusing the SAME
  /// `PlaybackProgressBarView` leaf `player_shell_view.dart`'s own clean-mode VOD transport bar
  /// uses, UNMODIFIED and NOT wrapped in `IgnorePointer` — see [_splashScreen] /
  /// [_cleanModeProgressBar].
  ///
  /// SCOPE NOTE: this surface only renders correctly GIVEN a `cleanMode` value — it does NOT
  /// derive one itself (one-way data flow, per this file's own SUB-VIEW INPUT PATTERN doc
  /// comment). A REAL value now reaches here end-to-end at runtime: `MomentsOverlayView`
  /// (`moments_view.dart`) forwards its own `cleanMode` field verbatim to this parameter, and the
  /// turnkey drop-in container (`reference_ui_design.dart`) forwards the SAME
  /// `PlayerOverlayContext.cleanMode` it already forwards to `FeedWinOverlayView` — the live value
  /// bubbled up from `PlayerShellView`'s own `_cleanMode` gesture state via `live_buy_player.dart`.
  /// See design.md D8 (`rb-flutter-clean-mode-upcoming-intro-coverage`) for the full cleanMode
  /// wiring chain, and this change's own design.md Decisions D2/D3
  /// (`rb-flutter-intro-progress-bar-interactive`) for how [introPosition] / [introDuration] /
  /// [introIsPlaying] / [onTogglePlayPause] / [onSeek] now reach here with real values instead of
  /// staying at their old static defaults.
  final bool cleanMode;

  /// The opening MP4 preroll's OWN current playback position, in seconds — NOT the main video's
  /// position. Only read while [cleanMode] is `true`; ignored (and the progress bar not composed
  /// at all) otherwise. Default `0` (inert for any call site that doesn't also pass
  /// `cleanMode: true`). At runtime (rb-flutter-intro-progress-bar-interactive) `MomentsOverlayView`
  /// supplies the REAL value from `MomentsModel.introPosition`, which reads the SAME shared
  /// `DefaultPlayerTemplate.playbackProgress` the VOD progress bar reads — native now reports the
  /// intro player's own progress through that identical channel while `splash` is active.
  final double introPosition;

  /// The opening MP4 preroll's OWN total duration, in seconds — companion to [introPosition].
  /// Default `0` (`playbackProgressRatio`'s own `duration <= 0` fallback renders an empty bar,
  /// so an unwired default stays visually inert rather than throwing). Same real-value sourcing
  /// as [introPosition] at runtime.
  final double introDuration;

  /// Whether the opening MP4 preroll is currently playing — companion to [introPosition] /
  /// [introDuration] (rb-flutter-intro-progress-bar-interactive, ADDED). Drives the clean-mode
  /// progress bar's play/pause glyph. Default `true` — source-compat with the prior hardcoded
  /// visual for any existing `cleanMode: true` call site that doesn't also pass this explicitly
  /// (see design.md D4 for why this widget-level default differs from
  /// `MomentsModel.introIsPlaying`'s own `false` demo default). At runtime `MomentsOverlayView`
  /// supplies the real value from `MomentsModel.introIsPlaying`.
  final bool introIsPlaying;

  /// Clean-mode progress bar play/pause tap (rb-flutter-intro-progress-bar-interactive, ADDED) —
  /// forwarded verbatim to the composed `PlaybackProgressBarView.onTogglePlayPause`. Only
  /// reachable while [cleanMode] is `true` (the bar isn't composed otherwise). `null` (default)
  /// → inert (demo / golden / standalone), same SUB-VIEW INPUT PATTERN as [onSkip].
  final VoidCallback? onTogglePlayPause;

  /// Clean-mode progress bar drag-seek (rb-flutter-intro-progress-bar-interactive, ADDED) —
  /// invoked with the resolved absolute seconds and [introDuration] enriched in, matching
  /// `PlayerShellView.onSeek`'s exact `(seconds, {duration})` contract so a host can wire the SAME
  /// handler to both. `null` (default) → inert.
  final void Function(double seconds, {double? duration})? onSeek;

  /// Splash「略過介紹」open intent. This surface does NOT own the skip — the
  /// container / host funnels it to core `skipStart()`. `null` for demo / golden
  /// instances — the pill renders correctly action-free.
  final VoidCallback? onSkip;

  const StartScreenView({
    super.key,
    required this.theme,
    required this.phase,
    this.coverUrl = '',
    this.live = false,
    this.cleanMode = false,
    this.introPosition = 0,
    this.introDuration = 0,
    this.introIsPlaying = true,
    this.onTogglePlayPause,
    this.onSeek,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case LBPStartPhase.loading:
        return _loadingScreen();
      case LBPStartPhase.buffering:
        // Renders NOTHING (rb-flutter-intro-chrome-buffering-parity, parity to iOS): when the
        // playback engine stalls the canonical state stays `buffering`, so the phase stayed
        // buffering and the central spinner remained stuck on screen. Draw nothing; initial-load
        // feedback is the loading full-bleed brand loader.
        return const SizedBox.shrink();
      case LBPStartPhase.splash:
        return _splashScreen(context);
      case LBPStartPhase.done:
        // `done`: no overlay. The container short-circuits this branch, but the
        // sub-view stays self-consistent (renders nothing).
        return const SizedBox.shrink();
    }
  }

  // MARK: - loading — full-bleed brand loader (design `phase === 'loading'`)

  /// First load: a full-bleed dark brand background with a centered 17-frame
  /// brand-mark animation (`LoadingMarkAnimationView`,
  /// rb-flutter-loading-mark-png-sequence — replaces the former static
  /// `_spinnerRing()`) ONLY (`background: '#0C0C10'`). The brand wordmark
  /// (accent dot + `Livebuy`) and the「載入中…」caption that used to sit below
  /// the animation are REMOVED (rb-flutter-loading-announce-restyle, design
  /// re-sync `c3c98733`: `LBPLoadingOverlay` now renders only
  /// `<LBLoading size={76} />`).
  ///
  /// When [resolveLoadingCoverUrl] resolves a URL (`live == true` + non-empty
  /// [coverUrl]), the channel's real cover photo + a `rgba(0,0,0,0.35)` dark mask
  /// are overlaid UNDER the brand-mark animation, on top of (not replacing) the
  /// solid `_brandBackdrop` — parity iOS `StartScreenView.swift` / Android
  /// `StartScreenView.kt` / RN `StartScreenView.tsx`
  /// (`player-loading-cover-background-reference-ui-flutter`). `live == false` /
  /// empty [coverUrl] (every pre-existing call site, including demo / golden)
  /// keeps the exact pre-existing solid-backdrop widget tree, byte-identical.
  Widget _loadingScreen() {
    final String? resolvedCover =
        resolveLoadingCoverUrl(live: live, urlString: coverUrl);
    if (resolvedCover == null) {
      return ColoredBox(
        key: LbTestKeys.momentLoading,
        color: _brandBackdrop,
        child: const Center(
          child: LoadingMarkAnimationView(size: 76),
        ),
      );
    }
    return ColoredBox(
      key: LbTestKeys.momentLoading,
      color: _brandBackdrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Real cover photo (shared `liveProductImage` loader — see the
          // NETWORK-URI IMAGE EXCEPTION comment near the top of this file). No
          // placeholder needed here: the enclosing ColoredBox already IS the
          // solid brand backdrop underneath, so `liveProductImage`'s own
          // placeholder-on-load/-error fallback just needs to be transparent.
          liveProductImage(
            live: true,
            url: resolvedCover,
            placeholder: const SizedBox.shrink(),
            fit: BoxFit.cover,
          ),
          // Dark mask over the cover (`rgba(0,0,0,0.35)`).
          Container(
            key: LbTestKeys.momentLoadingCoverMask,
            color: Colors.black.withValues(alpha: 0.35),
          ),
          const Center(
            child: LoadingMarkAnimationView(size: 76),
          ),
        ],
      ),
    );
  }

  // MARK: - buffering — intentionally not rendered (rb-flutter-intro-chrome-buffering-parity)

  // MARK: - splash — skip-only overlay (bottom-right「略過介紹」skip pill)

  /// The opening video plays through the NORMAL playback path with the subject chrome
  /// (LIVE / VOD) visible behind — 開場不接管畫面 (start is NOT a screen takeover). The
  /// ONLY added UI is a bottom-right「略過介紹」skip pill. NO 片頭 tag / muted indicator /
  /// brand backdrop / lower-third title card / progress bar (all removed per the latest
  /// design `LBPSkipIntroButton` — the intro now plays unmuted with chrome). The overlay
  /// is transparent so the chrome behind shows through. Plain `Stack` / `Positioned`.
  ///
  /// The skip pill's `bottom` offset adds the system bottom safe area
  /// (`MediaQuery.of(context).padding.bottom`, fix-flutter-player-shell-bottom-safearea-gaps —
  /// replaces the prior literal `bottom: 16`), matching the same convention every other
  /// bottom-pinned player-shell chrome in this package uses, so the pill clears the home
  /// indicator / Android gesture bar on a real device. `right: 12` is unaffected.
  ///
  /// [cleanMode] (rb-flutter-clean-mode-upcoming-intro-coverage, Requirement B) flips this
  /// branch between its two mutually-exclusive presentations: `false` (default) draws ONLY the
  /// skip pill, byte-identical to before this change; `true` draws NO skip pill and instead an
  /// expanded, **fully interactive** [PlaybackProgressBarView]
  /// (rb-flutter-intro-progress-bar-interactive) bound to [introPosition] / [introDuration] /
  /// [introIsPlaying] — see [_cleanModeProgressBar].
  Widget _splashScreen(BuildContext context) {
    final double safeAreaBottom = MediaQuery.of(context).padding.bottom;
    return Stack(
      key: LbTestKeys.momentStart,
      fit: StackFit.expand,
      children: [
        if (!cleanMode)
          Positioned(
            right: 12,
            bottom: 16 + safeAreaBottom,
            child: _skipPill(),
          ),
        if (cleanMode) _cleanModeProgressBar(safeAreaBottom),
      ],
    );
  }

  /// Clean-mode's expanded, **fully interactive** progress bar
  /// (rb-flutter-intro-progress-bar-interactive — supersedes the read-only version
  /// `rb-flutter-clean-mode-upcoming-intro-coverage` shipped) — bound to [introPosition] /
  /// [introDuration] / [introIsPlaying] (the OPENING MP4's own playback, NOT the main video's, per
  /// those fields' own doc comments). Reuses `PlaybackProgressBarView` UNMODIFIED (same widget
  /// `player_shell_view.dart`'s own clean-mode VOD transport bar composes), forced to its expanded
  /// transport-bar visual (`scrubBarExpanded: true`) — matching the VOD reference visual this
  /// Requirement asks for ("視覺參考 VOD 展開態 transport bar"), now genuinely interactive to match
  /// too: [onTogglePlayPause] / [onSeek] are forwarded straight to the leaf's own
  /// `onTogglePlayPause` / `onSeek`, so tapping the play/pause button and dragging the track behave
  /// exactly like the VOD bar. `isScrubbing` stays fixed `false` (no floating drag timestamp
  /// readout — design.md D1: this bar is permanently forced-expanded, so there is no
  /// collapse-timer state machine like the VOD bar's `PlayerShellView._isScrubbing` to make that
  /// readout meaningful here; the drag itself still tracks the finger correctly via the leaf's own
  /// internal `_dragRatio`, independent of `isScrubbing`). NOT wrapped in `IgnorePointer` — every
  /// one of `PlaybackProgressBarView`'s own gesture handlers IS reachable now.
  Widget _cleanModeProgressBar(double safeAreaBottom) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: splashProgressBarBottomInset(safeAreaBottom,
          isAndroid: defaultTargetPlatform == TargetPlatform.android),
      child: PlaybackProgressBarView(
        theme: theme,
        position: introPosition,
        duration: introDuration,
        isPlaying: introIsPlaying,
        isScrubbing: false,
        scrubBarExpanded: true,
        onTogglePlayPause: onTogglePlayPause,
        onSeek: (seconds) => onSeek?.call(seconds, duration: introDuration),
      ),
    );
  }

  /// Bottom-right skip pill (`略過介紹` → onSkip): a translucent dark capsule with a
  /// soft shadow + a STATIC「略過介紹」label (no `(N)` countdown —
  /// rb-ios-skip-intro-label-static). This surface NEVER auto-fires skip on any timer;
  /// tapping forwards [onSkip].
  Widget _skipPill() {
    return GestureDetector(
      key: LbTestKeys.momentStartSkip,
      behavior: HitTestBehavior.opaque,
      onTap: onSkip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _chromeFill.withValues(alpha: 0.6), // rgba(20,20,24,0.6)
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3), // rgba(0,0,0,0.3)
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _skipLabel,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13 * theme.fontScale,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            // Fast-forward chevrons (the design's `M5 4l8 8…M14 4l6 8…` SVG):
            // self-drawn open double chevron » (stroke), matching iOS/Android
            // ChevronForwardGlyph (rb-flutter-icon-parity-composer-skip-pip-batch — this
            // comment previously claimed parity before the glyph actually existed here).
            const ChevronForwardGlyph(color: Colors.white, size: 13),
          ],
        ),
      ),
    );
  }

}
