import 'package:flutter/widgets.dart';

// MARK: - ShareGlyph — self-drawn three-node share glyph (design `Icons.share`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-share-icon-design-align, 問題 8).
// Flutter parity of iOS `Glyphs/ShareGlyph.swift` / Android `ShareGlyph.kt` (34dfec3 / 76ce565).
//
// One shared hand-drawn share glyph replacing the prior Material `Icons.ios_share` / emoji `↑`
// across the side rail / LIVE bottom bar / product-detail footer / product-list row. Drawn in a
// 24-unit space: three r=2.5 stroked nodes at (6,12) / (18,6) / (18,18) + two round-cap lines
// (8,11)→(16,7) and (8,13)→(16,17). Stroke width 1.8 (scaled). Identical geometry to iOS/Android.

/// The self-drawn three-node share glyph. [size] is the square edge (the design uses ~18–20).
class ShareGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const ShareGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShareGlyphPainter(color)),
    );
  }
}

class _ShareGlyphPainter extends CustomPainter {
  final Color color;
  _ShareGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final sw = 1.8 * s;
    final r = 2.5 * s;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;

    // Three stroked nodes at (6,12) / (18,6) / (18,18).
    for (final node in const [Offset(6, 12), Offset(18, 6), Offset(18, 18)]) {
      canvas.drawCircle(Offset(node.dx * s, node.dy * s), r, stroke);
    }
    // Two connecting lines: (8,11)→(16,7) and (8,13)→(16,17).
    canvas.drawLine(Offset(8 * s, 11 * s), Offset(16 * s, 7 * s), stroke);
    canvas.drawLine(Offset(8 * s, 13 * s), Offset(16 * s, 17 * s), stroke);
  }

  @override
  bool shouldRepaint(covariant _ShareGlyphPainter old) => old.color != color;
}
