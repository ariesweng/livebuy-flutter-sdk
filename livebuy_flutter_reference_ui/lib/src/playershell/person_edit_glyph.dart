import 'package:flutter/widgets.dart';

// MARK: - PersonEditGlyph — self-drawn person-edit (head + pencil badge) nickname icon
//
// Spec: `reference-ui-rendering/spec.md` (rb-align-nickname-icon-person-edit).
// Flutter parity of iOS `Glyphs/PersonEditGlyph.swift` / Android `PersonEditGlyph.kt` / RN
// `PersonEditGlyph.tsx`. Design `design/templates/minimal/live-chrome.jsx` `LBLiveBottomBar`
// 設定暱稱 button (≈224):
//   <circle cx=10 cy=8 r=3.2/>             head
//   <path d="M3 21c0-4 3-6 7-6"/>          shoulders
//   <path d="M14 18l5-5 2 2-5 5h-2v-2z"/>  pencil badge (bottom-right)
//   (24px viewBox, strokeWidth 1.8, round cap/join, fill none).
//
// The LIVE bottom bar's nickname button previously drew the head-only Material `Icons.person`,
// which diverges from the design's person-EDIT composite (head + a pencil badge). Hand-drawn so
// all four platforms render the SAME glyph. Geometry mirrors the 24-unit space, scaled by
// `size/24` (identical to `ShareGlyph`).

/// The self-drawn person-edit glyph (head + shoulders + pencil badge). [size] is the square edge.
class PersonEditGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const PersonEditGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PersonEditGlyphPainter(color)),
    );
  }
}

class _PersonEditGlyphPainter extends CustomPainter {
  final Color color;
  _PersonEditGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Head: stroked circle cx=10 cy=8 r=3.2.
    canvas.drawCircle(Offset(10 * s, 8 * s), 3.2 * s, stroke);

    // Shoulders: M3 21 c0 -4 3 -6 7 -6  → cubic (3,21) → ctrl (3,17),(6,15) → (10,15).
    final shoulders = Path()
      ..moveTo(3 * s, 21 * s)
      ..cubicTo(3 * s, 17 * s, 6 * s, 15 * s, 10 * s, 15 * s);
    canvas.drawPath(shoulders, stroke);

    // Pencil: M14 18 l5 -5 l2 2 l-5 5 h-2 v-2 z  (closed outline, bottom-right).
    final pencil = Path()
      ..moveTo(14 * s, 18 * s)
      ..lineTo(19 * s, 13 * s)
      ..lineTo(21 * s, 15 * s)
      ..lineTo(16 * s, 20 * s)
      ..lineTo(14 * s, 20 * s)
      ..close();
    canvas.drawPath(pencil, stroke);
  }

  @override
  bool shouldRepaint(covariant _PersonEditGlyphPainter old) => old.color != color;
}
