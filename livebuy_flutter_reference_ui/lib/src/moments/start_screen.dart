import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show LBPStartPhase;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
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
//   2. its bound SNAPSHOT VALUE                — `phase: LBPStartPhase`, the
//      read-only mirror of `DefaultStartScreenState.phase`, passed BY VALUE from
//      `MomentsModel.startPhase` (never the model, never the template).
//   3. one optional action callback, trailing, defaulting to `null` (`onSkip`).
//      The container / host wires it to the core player exit (`skipStart()`); this
//      surface does NOT own the skip intent and renders correctly with it null (so
//      demo / golden / widget tests construct it action-free).
//
// One-way data flow: this view reads ONLY its passed-in `phase` — it never reaches
// back into `MomentsModel` or `DefaultPlayerTemplate`, never holds a second copy of
// the phase, and NEVER drives the skip itself. The splash skip pill shows a STATIC
// 「略過介紹」label (rb-ios-skip-intro-label-static — no `(N)` countdown). The host
// wires `onSkip` to core `skipStart()`; this layer only FORWARDS the CTA tap.
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

// MARK: - Fixed decorative design tokens (literal minimal hex via colorFromHex)

/// Loading brand backdrop (`background: '#0C0C10'`).
final Color _brandBackdrop = colorFromHex('#0C0C10') ?? const Color(0xFF0C0C10);

/// Chrome capsule fill (`rgba(20,20,24,…)`).
final Color _chromeFill = colorFromHex('#141418') ?? const Color(0xFF141418);

// MARK: - Fixed localized copy (static presentation strings — parity to iOS/Android)

// rb-ios-skip-intro-label-static (four-platform parity): the skip pill shows a STATIC
// 「略過介紹」label with NO `(N)` countdown (the host wires `onSkip` → core `skipStart()`).
const String _skipLabel = '略過介紹';

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

  /// Splash「略過介紹」open intent. This surface does NOT own the skip — the
  /// container / host funnels it to core `skipStart()`. `null` for demo / golden
  /// instances — the pill renders correctly action-free.
  final VoidCallback? onSkip;

  const StartScreenView({
    super.key,
    required this.theme,
    required this.phase,
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
        return _splashScreen();
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
  Widget _loadingScreen() {
    return ColoredBox(
      key: LbTestKeys.momentLoading,
      color: _brandBackdrop,
      child: const Center(
        child: LoadingMarkAnimationView(size: 76),
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
  Widget _splashScreen() {
    return Stack(
      key: LbTestKeys.momentStart,
      fit: StackFit.expand,
      children: [
        Positioned(
          right: 12,
          bottom: 16,
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
            // open double chevron » (stroke), matching iOS/Android ChevronForwardGlyph.
            const Icon(Icons.keyboard_double_arrow_right, size: 13, color: Colors.white),
          ],
        ),
      ),
    );
  }

}
