import 'package:flutter/widgets.dart';

// MARK: - PipGlyph — self-drawn frame + inset rect + directional arrow glyph
//                     (design `Icons.pip`)
//
// Design: `design/shared/icons.jsx` `Icons.pip` (24px viewBox):
//   outer frame  <rect x=3  y=5  width=18 height=14 rx=2/>            (stroke, fill none)
//   inset rect   <rect x=11 y=11 width=8  height=6  rx=1/>            (filled, no stroke)
//   arrow        <path d="M7 8.5L9.6 11.1M9.6 8.5v2.6h-2.6"/>          (stroke, fill none)
//
// Ported from iOS `PipGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/PipGlyph.swift`,
// rb-ios-icon-parity, 2026-08-25 redesign — adds a directional/minimize arrow onto the
// pre-existing frame+small-rect PiP-style motif). Replaces the player header's minimize
// button's Material `Icons.picture_in_picture_alt` in the `showCloseIcon == false` branch
// ONLY (`rb-flutter-icon-parity-composer-skip-pip-batch`); `showCloseIcon == true`'s
// `Icons.close` is a separate, unrelated feature and is untouched by this glyph.
//
// Two layers: outer frame + arrow (one stroked `Path`, 3 subpaths) + inset rect (filled) —
// `addRoundedRect(cornerSize:)` maps to `canvas.drawRRect(RRect.fromRectAndRadius(...))`;
// both rects here have equal corner width/height so `Radius.circular` is sufficient.

/// The design's frame + inset-rect + directional-arrow glyph. [size] is the square edge;
/// [color] drives BOTH the stroke and the fill (per the design).
class PipGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const PipGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PipGlyphPainter(color)),
    );
  }
}

class _PipGlyphPainter extends CustomPainter {
  final Color color;
  _PipGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Outer frame (rounded rect x=3 y=5 w=18 h=14 rx=2) + minimize-direction arrow, both
    // stroked at the same width, one Path with 3 subpaths.
    final framePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(3 * s, 5 * s, 18 * s, 14 * s),
        Radius.circular(2 * s),
      ))
      // Arrow diagonal — M7 8.5 L9.6 11.1.
      ..moveTo(7 * s, 8.5 * s)
      ..lineTo(9.6 * s, 11.1 * s)
      // Arrow corner — M9.6 8.5 v2.6 h-2.6 -> (9.6,8.5) -> (9.6,11.1) -> (7,11.1).
      ..moveTo(9.6 * s, 8.5 * s)
      ..lineTo(9.6 * s, 11.1 * s)
      ..lineTo(7 * s, 11.1 * s);
    canvas.drawPath(framePath, stroke);

    // Inset rect (the "screen" of the PiP frame) — filled, x=11 y=11 w=8 h=6 rx=1.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(11 * s, 11 * s, 8 * s, 6 * s),
        Radius.circular(1 * s),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _PipGlyphPainter old) => old.color != color;
}
