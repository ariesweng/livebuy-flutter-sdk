import 'package:flutter/widgets.dart';

// MARK: - ChevronForwardGlyph — self-drawn open double-chevron skip glyph
//                                (design skip path)
//
// Design: `design/shared/icons.jsx` skip path + `design/templates/minimal/moments.jsx`
// `LBPSkipIntroButton` — `fill="none" stroke="#fff" strokeWidth="2.2" strokeLinecap/
// Linejoin="round"`: `<path d="M5 4l8 8-8 8M14 4l6 8-6 8"/>` = two OPEN `>` chevrons (NOT
// filled triangles).
//
// Ported from iOS `ChevronForwardGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// ChevronForwardGlyph.swift`, rb-ios-fill-stroke-align). Replaces the intro StartScreen's
// 「略過介紹」skip pill's Material `Icons.keyboard_double_arrow_right`
// (`rb-flutter-icon-parity-composer-skip-pip-batch`) — the call site's own comment already
// claimed parity with this glyph before it existed; this change makes that claim true.
//
// Single stroked `Path`, two open `>` polylines — no fill layer needed.

/// The design's open double-chevron skip glyph (two stroked `>` polylines). [size] is the
/// square edge.
class ChevronForwardGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const ChevronForwardGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ChevronForwardGlyphPainter(color)),
    );
  }
}

class _ChevronForwardGlyphPainter extends CustomPainter {
  final Color color;
  _ChevronForwardGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      // Chevron 1: M5 4 l8 8 -8 8 -> (5,4) -> (13,12) -> (5,20).
      ..moveTo(5 * s, 4 * s)
      ..lineTo(13 * s, 12 * s)
      ..lineTo(5 * s, 20 * s)
      // Chevron 2: M14 4 l6 8 -6 8 -> (14,4) -> (20,12) -> (14,20).
      ..moveTo(14 * s, 4 * s)
      ..lineTo(20 * s, 12 * s)
      ..lineTo(14 * s, 20 * s);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ChevronForwardGlyphPainter old) => old.color != color;
}
