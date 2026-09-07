import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// MARK: - LockGlyph — self-drawn closed-padlock glyph (design `Icons.lock`)
//
// Design: `design/shared/icons.jsx` `Icons.lock` (24px viewBox):
//   shackle       M6.48 8.64 A5.52 5.28 0 0 1 17.52 8.64   (stroke 2.64, fill none,
//                                                             elliptical arc rx=5.52 ry=5.28)
//   drop lines    M6.48 8.64 L6.48 11.04  M17.52 8.64 L17.52 11.04   (stroke 2.64)
//   body          <rect x=4.8 y=9.6 width=14.4 height=11.52 rx=2.64/>  (filled)
// A CLOSED padlock (shackle connects to the body).
//
// Ported from iOS `LockGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// LockGlyph.swift`). iOS hand-expands the shackle's elliptical arc into 2 manual
// cubic-bezier segments (`startDegrees: 180, endDegrees: 270` then
// `startDegrees: 270, endDegrees: 360` — 9 o'clock → 12 o'clock → 3 o'clock, the
// SHORT/upper way) because the SwiftUI `Path` version it targets has no native
// arc-drawing API (an iOS-14 compatibility workaround). Dart's
// `Path.addArc(Rect, double startAngle, double sweepAngle)` DOES have a native arc
// primitive (angles in radians), so this port uses it directly instead of
// replicating the workaround — same geometry, one arc call instead of two segments.
//
// Angle convention: both Flutter and SwiftUI use a y-down coordinate system where
// `startAngle`/`sweepAngle` are measured from the 3-o'clock direction, positive =
// clockwise on screen — the same convention as iOS's `startDegrees`/`endDegrees`
// (see `ArrowClockwiseGlyph`'s port for the same convention note). Cross-checking
// iOS's own annotation against that convention: 180° = 9 o'clock, 270° = 12
// o'clock, 360°(=0°) = 3 o'clock — clockwise from 3 o'clock by 180°/270°/360°
// lands exactly on 9/12/3 o'clock respectively, confirming the convention. The
// combined arc therefore sweeps 180° total, starting at 180° and ending at 360°,
// tracing west → north (arc apex) → east — the UPPER half of the ellipse (the
// shackle's dome shape sitting above the lock body, open at the bottom where it
// meets the two drop lines). Converted to Flutter: `startAngle = math.pi` (180°),
// `sweepAngle = math.pi` (the 180° span from 180° to 360° — NOT `math.pi / 2`,
// which would only sweep a quarter-turn and draw the wrong shape).
//
// Hand-verified against the rendered `auth-gate-modal.png` golden: the shackle
// draws as an upper-half arch (NOT a lower half / NOT a full circle / NOT a
// quarter arc), matching the closed padlock silhouette.
//
// Sole call site: `gapsurfaces/auth_gate_modal.dart`'s `_lockBadge()` (replaces
// Material `Icons.lock_outline`).

/// The self-drawn closed-padlock glyph (shackle arch + 2 drop lines + filled
/// rounded-rect body). [size] is the square edge.
class LockGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const LockGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LockGlyphPainter(color)),
    );
  }
}

class _LockGlyphPainter extends CustomPainter {
  final Color color;
  _LockGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.64 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(12 * s, 8.64 * s);
    final rx = 5.52 * s;
    final ry = 5.28 * s;

    // Shackle arch: 180° (9 o'clock) -> 360° (3 o'clock) via 270° (12 o'clock) —
    // the upper half of the ellipse. Native addArc (one call, not iOS's 2 manual
    // Bezier segments).
    final shacklePath = Path()
      ..addArc(
        Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
        math.pi, // startAngle 180°
        math.pi, // sweepAngle 180° (180° -> 360°)
      );

    // Drop lines.
    shacklePath.moveTo(6.48 * s, 8.64 * s);
    shacklePath.lineTo(6.48 * s, 11.04 * s);
    shacklePath.moveTo(17.52 * s, 8.64 * s);
    shacklePath.lineTo(17.52 * s, 11.04 * s);

    canvas.drawPath(shacklePath, stroke);

    // Body: filled rounded rect x=4.8 y=9.6 w=14.4 h=11.52 rx=2.64.
    final bodyPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(4.8 * s, 9.6 * s, 14.4 * s, 11.52 * s),
        Radius.circular(2.64 * s),
      ));
    canvas.drawPath(bodyPath, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LockGlyphPainter old) => old.color != color;
}
