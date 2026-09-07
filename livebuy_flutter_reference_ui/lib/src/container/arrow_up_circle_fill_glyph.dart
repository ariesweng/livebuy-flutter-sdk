import 'package:flutter/widgets.dart';

// MARK: - ArrowUpCircleFillGlyph — self-drawn filled-disc + white-arrow send glyph
//                                  (design `Icons.arrowUpCircleFill`)
//
// Design: `design/shared/icons.jsx` `Icons.arrowUpCircleFill` (24px viewBox):
//   circle  <circle cx=12 cy=12 r=10/>                    (filled, `color`)
//   arrow   M12 15.5V8.5  M8.3 12.2L12 8.5L15.7 12.2       (stroke, FIXED white — always
//           white regardless of `color`, the `color` param only tints the background disc)
//
// Ported from iOS `ArrowUpCircleFillGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// ArrowUpCircleFillGlyph.swift`, rb-ios-icon-parity). Replaces the on-demand chat composer's
// `Icons.send` (`rb-flutter-icon-parity-composer-skip-pip-batch`), parity with Android's own
// `ArrowUpCircleFillGlyph` (`openspec/specs/reference-ui-rendering/spec.md`, requirement
// 「Android on-demand chat composer 送出鈕為向量 glyph 對齊 icons.jsx arrowUpCircleFill」).
//
// Two draw styles (filled disc in `color`, stroked arrow ALWAYS white) need 2 Paint layers —
// same structure as `PipGlyph`'s stroke+fill split.

/// The design's filled-disc + white-cutout-arrow glyph. [size] is the square edge; [color]
/// tints ONLY the background disc — the arrow itself is always white (design-fixed).
class ArrowUpCircleFillGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const ArrowUpCircleFillGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ArrowUpCircleFillGlyphPainter(color)),
    );
  }
}

class _ArrowUpCircleFillGlyphPainter extends CustomPainter {
  final Color color;
  _ArrowUpCircleFillGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final arrowStroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Background disc: circle cx=12 cy=12 r=10 (filled, `color`).
    final r = 10 * s;
    canvas.drawCircle(Offset(12 * s, 12 * s), r, fill);

    // Arrow — shaft M12 15.5 V8.5 + chevron head M8.3 12.2 L12 8.5 L15.7 12.2. ALWAYS white.
    final arrow = Path()
      ..moveTo(12 * s, 15.5 * s)
      ..lineTo(12 * s, 8.5 * s)
      ..moveTo(8.3 * s, 12.2 * s)
      ..lineTo(12 * s, 8.5 * s)
      ..lineTo(15.7 * s, 12.2 * s);
    canvas.drawPath(arrow, arrowStroke);
  }

  @override
  bool shouldRepaint(covariant _ArrowUpCircleFillGlyphPainter old) => old.color != color;
}
