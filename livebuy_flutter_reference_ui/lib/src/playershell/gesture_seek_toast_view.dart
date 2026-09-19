import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';

// GestureSeekToastView — half-screen edge gradient + "10" + triple seek-horn glyph, transient
// visual feedback for a double-tap-seek hit (rb-flutter-double-tap-seek-feedback).
//
// Spec: `reference-ui-rendering/spec.md` — "Flutter player-shell 播放器手勢二度重寫..."
//   Requirement's 雙擊 seek 視覺回饋 paragraph + its new Scenarios.
// Design authority: `design/templates/minimal/sdk-components.jsx`'s `LBPGestureToast`
//   seekFwd/seekBack branch + its `LBPSeekHorn` helper (svg path
//   `M7.478 6.142l-6.242 4.39A.784.784 0 010 9.89V1.109A.784.784 0 011.236.468l6.242 4.39a.784.784
//   0 010 1.283z`, viewBox `0 0 8 11`) — NOT `openspec/specs/shared/design.md` §5.13, which is a
//   historical web `.fast`/`.bgleft`/`.bgright` reference only (see this change's design.md; the
//   two agree in visual language, sdk-components.jsx is the authority on any discrepancy).
//
// A SIBLING member of the same `LBPGestureToast` family as `GestureMuteToastView` (same design
// source, different visual branch — a half-screen edge gradient instead of a centre dark-glass
// pill) — but unlike `GestureMuteToastView` / `PlaybackPausedOverlayView` (retired-but-kept: no
// longer composed by `PlayerShellView`, see their own file headers), THIS widget IS actively
// composed by `PlayerShellView` — the double-tap-seek gesture it decorates (parity
// `rb-flutter-gesture-clean-mode-v2`) has had no visual feedback pathway of its own until this
// change.
//
// PURE presentation for the STATIC content (gradient / digit / horn glyphs) plus a
// self-contained 0.18s entrance fade — `TweenAnimationBuilder` animates automatically the moment
// this widget is first inserted into the tree, so no external `Timer`/state is needed to drive
// the fade-IN. It owns NO dismiss timer — `PlayerShellView` decides WHEN to mount/unmount this
// widget (mirrors `GestureMuteToastView`'s "no owned timer" precedent for the dismiss side; the
// entrance fade differs because it must always run exactly once on mount, with nothing external
// to drive it — there is no equivalent "caller flips a bool" seam for an enter-only animation).
class GestureSeekToastView extends StatelessWidget {
  /// The resolved reference-ui theme — only `theme.fontScale` is read (the "10" digit's font
  /// size), matching `GestureMuteToastView`'s own convention of taking `theme` purely for
  /// accessibility text scaling even though every color here is design-fixed (white glyphs on a
  /// black gradient), not theme-token-driven.
  final ReferenceUITheme theme;

  /// `true` — fast-forward (triggered by a double-tap-seek hit on the right half): gradient +
  /// content pinned to the right edge, horn row points right (unmirrored). `false` — rewind
  /// (left half): pinned to the left edge, horn row mirrored to point left.
  final bool isForward;

  const GestureSeekToastView({super.key, required this.theme, required this.isForward});

  static const Duration _fadeInDuration = Duration(milliseconds: 180);

  /// Design `rgba(0,0,0,0.8)` at the triggering edge fading to fully transparent at the 44%-width
  /// gradient's inner edge (`0xCC` == round(0.8 * 255)).
  static const Color _gradientStart = Color(0xCC000000);
  static const Color _gradientEnd = Color(0x00000000);

  @override
  Widget build(BuildContext context) {
    final edgeAlignment = isForward ? Alignment.centerRight : Alignment.centerLeft;
    return IgnorePointer(
      // Design `pointerEvents: 'none'` — a transient decoration, never blocks the video-area tap
      // detector (or anything else) underneath.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: _fadeInDuration,
        curve: Curves.easeOut,
        builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
        child: Align(
          alignment: edgeAlignment,
          child: FractionallySizedBox(
            // Design `width: '44%'`, full video-area height.
            widthFactor: 0.44,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: edgeAlignment,
                  end: isForward ? Alignment.centerLeft : Alignment.centerRight,
                  colors: const [_gradientStart, _gradientEnd],
                ),
              ),
              child: Align(
                alignment: edgeAlignment,
                child: Padding(
                  // Design `padding: isFwd ? '0 28px 0 0' : '0 0 0 28px'`.
                  padding: EdgeInsets.only(
                    right: isForward ? 28 : 0,
                    left: isForward ? 0 : 28,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '10',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24 * theme.fontScale,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Design: the horn row (not the digit) mirrors via `scaleX(-1)` for rewind.
                      Transform.flip(
                        flipX: !isForward,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SeekHorn(opacity: 0.3),
                            SizedBox(width: 4),
                            _SeekHorn(opacity: 0.5),
                            SizedBox(width: 4),
                            _SeekHorn(opacity: 1),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single `LBPSeekHorn` glyph — a rounded-back, right-pointing triangle (an 8×11 "play button"
/// shape), self-drawn to mirror this codebase's existing glyph-file convention (e.g.
/// `arrow_down_glyph.dart`'s `s = size.shortestSide / viewBoxEdge` scale factor). [opacity] is
/// applied per-instance so the three-horn row can fade from 0.3 (outermost) to 1 (innermost,
/// design `LBPSeekHorn size={8}` with no `style` override on the last one).
class _SeekHorn extends StatelessWidget {
  final double opacity;

  const _SeekHorn({required this.opacity});

  /// Design `<LBPSeekHorn size={8} .../>` — `size` is the width; height is `size * 11 / 8`
  /// (viewBox `0 0 8 11`).
  static const double _width = 8;
  static const double _height = _width * 11 / 8;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: const SizedBox(
        width: _width,
        height: _height,
        child: CustomPaint(painter: _SeekHornPainter()),
      ),
    );
  }
}

class _SeekHornPainter extends CustomPainter {
  const _SeekHornPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox `0 0 8 11` — scale by width (8 units) since `_SeekHorn` always sizes height as
    // `width * 11 / 8`, keeping the aspect ratio locked.
    final s = size.width / 8;
    final path = Path()
      // SVG `M7.478 6.142 l-6.242 4.39` — the pointed right-hand tip, then a straight edge down
      // to the bottom-left rounded corner's start.
      ..moveTo(7.478 * s, 6.142 * s)
      ..lineTo(1.236 * s, 10.532 * s)
      // SVG `A.784.784 0 010 9.89` — rounded bottom-left corner.
      ..arcToPoint(Offset(0, 9.89 * s), radius: Radius.circular(0.784 * s), clockwise: true)
      // SVG `V1.109` — the flat left edge.
      ..lineTo(0, 1.109 * s)
      // SVG `A.784.784 0 011.236.468` — rounded top-left corner.
      ..arcToPoint(Offset(1.236 * s, 0.468 * s), radius: Radius.circular(0.784 * s), clockwise: true)
      // SVG `l6.242 4.39` — straight edge back up to just short of the tip.
      ..lineTo(7.478 * s, 4.858 * s)
      // SVG `a.784.784 0 010 1.283 z` — rounded tip, closing the path back at the start point.
      ..arcToPoint(Offset(7.478 * s, 6.141 * s), radius: Radius.circular(0.784 * s), clockwise: true)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _SeekHornPainter oldDelegate) => false;
}
