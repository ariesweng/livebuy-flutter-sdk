import 'package:flutter/widgets.dart';

// MARK: - HourglassGlyph — self-drawn hourglass (design `Icons.hourglass`)
//
// Spec: `reference-ui-rendering/spec.md`（rb-flutter-flash-sale-bid，搶購場商品明細狀態（Flutter））.
// Flutter parity of iOS `Glyphs/HourglassGlyph.swift` / Android `IconGlyphs.kt` `HourglassGlyph` /
// RN `HourglassGlyph.tsx`. Call site: the 14pt icon in the「正在等待結果...」banner
// (`screens.jsx` `LBPBidWaitingBanner`, `stroke={2}`, white).
//
// Drawn in a 24-unit space (scaled by `s = size/24`), tracing `design/shared/icons.jsx`
// `Icons.hourglass`. The path has NO arc (`icon-authoring.md` rule 1 does not apply); the relative
// `h` / `v` / `c` commands are resolved to absolute coordinates below:
//   frame  M6 3h12M6 21h12                                         (stroked)
//   walls  M7.5 3v2.5c0 2.2 1.8 3.7 4.5 6.5c-2.7 2.8-4.5 4.3-4.5 6.5V21
//          M16.5 3v2.5c0 2.2-1.8 3.7-4.5 6.5c2.7 2.8 4.5 4.3 4.5 6.5V21   (stroked)
//   sand   M9.3 18.6h5.4c0-1.3-1.3-2.5-2.7-3.8c-1.4 1.3-2.7 2.5-2.7 3.8z  (filled, no stroke)
// Frame + walls share one stroke Path (round cap / join, like every stroked `Icon` in icons.jsx);
// the sand pile is a separate fill Path. Fill and stroke share [color].

/// The self-drawn hourglass glyph (stroked frame + walls, filled sand pile). [size] is the square
/// edge; [strokeWidth] is in the 24-unit space (design call site `stroke={2}`).
class HourglassGlyph extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;

  const HourglassGlyph({
    super.key,
    required this.color,
    this.size = 14,
    this.strokeWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HourglassGlyphPainter(color, strokeWidth)),
    );
  }
}

class _HourglassGlyphPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  _HourglassGlyphPainter(this.color, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final outline = Path()
      // Frame bars.
      ..moveTo(6 * s, 3 * s)
      ..lineTo(18 * s, 3 * s)
      ..moveTo(6 * s, 21 * s)
      ..lineTo(18 * s, 21 * s)
      // Left wall.
      ..moveTo(7.5 * s, 3 * s)
      ..lineTo(7.5 * s, 5.5 * s)
      ..cubicTo(7.5 * s, 7.7 * s, 9.3 * s, 9.2 * s, 12 * s, 12 * s)
      ..cubicTo(9.3 * s, 14.8 * s, 7.5 * s, 16.3 * s, 7.5 * s, 18.5 * s)
      ..lineTo(7.5 * s, 21 * s)
      // Right wall.
      ..moveTo(16.5 * s, 3 * s)
      ..lineTo(16.5 * s, 5.5 * s)
      ..cubicTo(16.5 * s, 7.7 * s, 14.7 * s, 9.2 * s, 12 * s, 12 * s)
      ..cubicTo(14.7 * s, 14.8 * s, 16.5 * s, 16.3 * s, 16.5 * s, 18.5 * s)
      ..lineTo(16.5 * s, 21 * s);
    canvas.drawPath(outline, stroke);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final sand = Path()
      ..moveTo(9.3 * s, 18.6 * s)
      ..lineTo(14.7 * s, 18.6 * s)
      ..cubicTo(14.7 * s, 17.3 * s, 13.4 * s, 16.1 * s, 12 * s, 14.8 * s)
      ..cubicTo(10.6 * s, 16.1 * s, 9.3 * s, 17.3 * s, 9.3 * s, 18.6 * s)
      ..close();
    canvas.drawPath(sand, fill);
  }

  @override
  bool shouldRepaint(covariant _HourglassGlyphPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
