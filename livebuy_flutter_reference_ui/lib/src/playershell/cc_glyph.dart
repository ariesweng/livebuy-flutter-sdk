import 'package:flutter/widgets.dart';

// MARK: - CcGlyph — self-drawn subtitle/CC glyph (design `Icons.cc`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-cc-icon-design-align). Used by the
// side-rail subtitle pill in `operation_rail.dart` (`_PillButton`'s `LBSideRailKind.subtitle`
// case), which previously drew the Material `Icons.closed_caption` — a rounded-square-with-two-
// blocks glyph that does not match the design's hand-drawn double-"C" badge.
//
// Design `design/shared/icons.jsx` `Icons.cc` (`cc:` key, ~line 23), 24-unit viewBox, strokeWidth
// 1.8, fill: none:
//   <rect x="3" y="5" width="18" height="14" rx="3" />   badge frame (stroke)
//   <path d="M9 11c-.5-.6-1.3-1-2-1-1.4 0-2.5 1.1-2.5 2.5S5.6 15 7 15c.7 0 1.5-.4 2-1
//             M16 11c-.5-.6-1.3-1-2-1-1.4 0-2.5 1.1-2.5 2.5S12.6 15 14 15c.7 0 1.5-.4 2-1" />
//                                                          two open "C" curves (stroke)
//
// The SVG path uses relative `c` cubic-bezier commands plus an absolute `S` (smooth) continuation.
// Hand-expanded to absolute-coordinate cubic segments (24-unit space) below — the right "C" is the
// left "C" shifted +7 on the x axis, y unchanged:
//
//   left C:  start (9,11)
//            cubicTo cp1(8.5,10.4)  cp2(7.7,10)   end(7,10)
//            cubicTo cp1(5.6,10)    cp2(4.5,11.1) end(4.5,12.5)
//            cubicTo cp1(4.5,13.9)  cp2(5.6,15)   end(7,15)
//            cubicTo cp1(7.7,15)    cp2(8.5,14.6) end(9,14)
//   right C: same 4 segments, every x + 7 (start (16,11) ... end (16,14))
//
// Geometry mirrors the 24-unit space, scaled by `size/24` (identical convention to
// `ShareGlyph`/`DetailGlyph`/`PersonEditGlyph`). No iOS/RN parity file is introduced by this
// change — Android already has its own `CcGlyph` (see `openspec/specs/reference-ui-rendering/
// spec.md`); iOS/RN CC glyph parity remain unfixed, tracked separately.

/// The self-drawn subtitle/CC glyph (rounded badge frame + two open "C" curves). [size] is the
/// square edge.
class CcGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const CcGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CcGlyphPainter(color)),
    );
  }
}

class _CcGlyphPainter extends CustomPainter {
  final Color color;
  _CcGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Badge frame: rounded rect x=3 y=5 w=18 h=14 rx=3 (stroke).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3 * s, 5 * s, 18 * s, 14 * s),
        Radius.circular(3 * s),
      ),
      stroke,
    );

    // Left "C": start (9,11) -> (7,10) -> (4.5,12.5) -> (7,15) -> (9,14).
    final left = Path()
      ..moveTo(9 * s, 11 * s)
      ..cubicTo(8.5 * s, 10.4 * s, 7.7 * s, 10 * s, 7 * s, 10 * s)
      ..cubicTo(5.6 * s, 10 * s, 4.5 * s, 11.1 * s, 4.5 * s, 12.5 * s)
      ..cubicTo(4.5 * s, 13.9 * s, 5.6 * s, 15 * s, 7 * s, 15 * s)
      ..cubicTo(7.7 * s, 15 * s, 8.5 * s, 14.6 * s, 9 * s, 14 * s);
    canvas.drawPath(left, stroke);

    // Right "C": left "C" shifted +7 on x.
    final right = Path()
      ..moveTo(16 * s, 11 * s)
      ..cubicTo(15.5 * s, 10.4 * s, 14.7 * s, 10 * s, 14 * s, 10 * s)
      ..cubicTo(12.6 * s, 10 * s, 11.5 * s, 11.1 * s, 11.5 * s, 12.5 * s)
      ..cubicTo(11.5 * s, 13.9 * s, 12.6 * s, 15 * s, 14 * s, 15 * s)
      ..cubicTo(14.7 * s, 15 * s, 15.5 * s, 14.6 * s, 16 * s, 14 * s);
    canvas.drawPath(right, stroke);
  }

  @override
  bool shouldRepaint(covariant _CcGlyphPainter old) => old.color != color;
}
