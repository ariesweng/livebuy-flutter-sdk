import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// MARK: - ArrowClockwiseGlyph — self-drawn refresh/reshuffle glyph
//                               (design `Icons.arrowClockwise`)
//
// Design: `design/shared/icons.jsx` `Icons.arrowClockwise` (24px viewBox, stroke 2,
// fill none):
//   arc     M19 12 A7 7 0 1 1 15.5 6.2   (large-arc=1 sweep=1 — clockwise the LONG
//                                          way, center (12,12) r=7, start (19,12) =
//                                          3 o'clock)
//   corner  M19 4.5 V9 H14.5              (arrowhead corner)
//
// Ported from iOS `ArrowClockwiseGlyph.swift` (`ios/Sources/LivebuyReferenceUI/
// Glyphs/ArrowClockwiseGlyph.swift`). iOS hand-expands the arc into 4 manual
// cubic-bezier segments (0°→90°→180°→270°→endDegrees) because the SwiftUI `Path`
// version it targets has no native arc-drawing API (an iOS-14 compatibility
// workaround). Dart's `Path.addArc(Rect, double startAngle, double sweepAngle)`
// DOES have a native arc primitive (angles in radians), so this port uses it
// directly instead of replicating the workaround — same geometry, fewer segments.
//
// Angle convention: both Flutter and SwiftUI use a y-down coordinate system where
// `startAngle`/`sweepAngle` are measured from the 3-o'clock direction, positive =
// clockwise on screen — the same convention as iOS's `startDegrees`/`endDegrees`.
// The end angle is derived via `atan2` (not hand-typed) exactly as iOS does: the
// raw angle to (15.5, 6.2) lands in the fourth quadrant (negative), and `< 270` is
// bumped by `+360` to force the "clockwise the long way" sweep (SVG large-arc=1)
// rather than the short way.
//
// Two call sites (`rb-flutter-icon-parity-error-retry-batch`): `error_screen.dart`
// `.stream` primary CTA (重試/retry) and `end_screen.dart`'s「換一批」reshuffle pill
// — both replace a Material `Icons.refresh*` glyph with this shared self-drawn one.

/// The self-drawn clockwise-refresh glyph (arc + arrowhead corner). [size] is the
/// square edge.
class ArrowClockwiseGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const ArrowClockwiseGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ArrowClockwiseGlyphPainter(color)),
    );
  }
}

class _ArrowClockwiseGlyphPainter extends CustomPainter {
  final Color color;
  _ArrowClockwiseGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(12 * s, 12 * s);
    final r = 7 * s;

    // The arc's end point (15.5, 6.2) — angle derived via atan2, not hand-typed.
    final endPoint = Offset(15.5 * s, 6.2 * s);
    final rawDegrees =
        math.atan2(endPoint.dy - center.dy, endPoint.dx - center.dx) *
            180 /
            math.pi;
    final endDegrees = rawDegrees < 270 ? rawDegrees + 360 : rawDegrees;

    // Native arc — startAngle 0 (3 o'clock), sweeping clockwise the long way to
    // endDegrees (mirrors SVG large-arc=1 sweep=1).
    final path = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: r),
        0,
        endDegrees * math.pi / 180,
      );

    // Arrowhead corner — M19 4.5 V9 H14.5.
    path.moveTo(19 * s, 4.5 * s);
    path.lineTo(19 * s, 9 * s);
    path.lineTo(14.5 * s, 9 * s);

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ArrowClockwiseGlyphPainter old) =>
      old.color != color;
}
