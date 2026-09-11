import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show LBPStartPhase;

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
//                   removed — 開場影片有聲、不接管畫面).
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
  Widget _splashScreen(BuildContext context) {
    final double safeAreaBottom = MediaQuery.of(context).padding.bottom;
    return Stack(
      key: LbTestKeys.momentStart,
      fit: StackFit.expand,
      children: [
        Positioned(
          right: 12,
          bottom: 16 + safeAreaBottom,
          child: _skipPill(),
        ),
      ],
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
