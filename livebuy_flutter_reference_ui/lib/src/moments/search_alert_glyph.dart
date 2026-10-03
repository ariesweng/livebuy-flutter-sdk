import 'package:flutter/widgets.dart';

// MARK: - SearchAlertGlyph — self-drawn「找不到影片」glyph
//                            (rb-flutter-error-notfound-glyph-parity)
// Design `design/templates/minimal/moments.jsx` `LBErrorScreen` → `config.notFound.icon`
// (24px viewBox, stroke 2, round cap/join):
//   lens         <circle cx=11 cy=11 r=7/>
//   handle       M21 21 L16.5 16.5
//   ! stem       M11 8 L11 11.5
//   ! dot        M11 14 (zero-length, round cap) → drawn as a filled circle r = stroke/2
// Same shape as RN `moments/SearchAlertGlyph.tsx`. Replaces Material `Icons.search_off_rounded`
// (a magnifier with an ×), which did not match the design.

/// The self-drawn「找不到影片」glyph (lens + handle + exclamation mark). [size] is the square edge.
class SearchAlertGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const SearchAlertGlyph({super.key, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SearchAlertGlyphPainter(color)),
    );
  }
}

class _SearchAlertGlyphPainter extends CustomPainter {
  final Color color;
  _SearchAlertGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(Offset(11 * s, 11 * s), 7 * s, stroke);
    canvas.drawLine(Offset(21 * s, 21 * s), Offset(16.5 * s, 16.5 * s), stroke);
    canvas.drawLine(Offset(11 * s, 8 * s), Offset(11 * s, 11.5 * s), stroke);
    canvas.drawCircle(
        Offset(11 * s, 14 * s), 1 * s, Paint()..color = color..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _SearchAlertGlyphPainter old) => old.color != color;
}
