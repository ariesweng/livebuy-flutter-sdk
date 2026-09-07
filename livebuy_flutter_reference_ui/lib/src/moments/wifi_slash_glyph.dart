import 'package:flutter/widgets.dart';

// MARK: - WifiSlashGlyph — self-drawn disconnected-wifi glyph
//                          (design `Icons.wifiSlash`)
//
// Design: `design/shared/icons.jsx` `Icons.wifiSlash` (24px viewBox):
//   arc 1 (near)  M8.5 15.3 Q12 12 15.5 15.3    (stroke 1.8, quadratic)
//   arc 2 (far)   M5 11.3 Q12 5.5 19 11.3        (stroke 1.8, quadratic)
//   dot           <circle cx=12 cy=19 r=1.3/>    (filled)
//   strike        M4 4 L20 20                    (stroke 2.2 — thicker)
//
// Ported from iOS `WifiSlashGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// WifiSlashGlyph.swift`). `addQuadCurve(to:control:)` maps to Dart's
// `Path.quadraticBezierTo(controlX, controlY, endX, endY)` — note the ARGUMENT
// ORDER DIFFERENCE: Dart takes control-point-then-end-point (same as iOS's
// `to: end, control: control` semantics, just a different parameter list order —
// do not swap them). Three independently-styled layers (two thin arcs, one filled
// dot, one thicker diagonal strike) map to 3 separate `Paint` objects painted via
// `canvas.drawPath` / `canvas.drawCircle`, mirroring the 3 separate SwiftUI `Path`
// + `.stroke`/`.fill` calls in the ZStack.
//
// Call site (`rb-flutter-icon-parity-error-retry-batch`): `error_screen.dart`
// `.stream` icon badge (串流錯誤斷網徽章), replacing Material `Icons.wifi_off_rounded`.

/// The self-drawn disconnected-wifi glyph (two signal arcs + dot + diagonal
/// strike). [size] is the square edge.
class WifiSlashGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const WifiSlashGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WifiSlashGlyphPainter(color)),
    );
  }
}

class _WifiSlashGlyphPainter extends CustomPainter {
  final Color color;
  _WifiSlashGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;

    // Two signal arcs — near M8.5 15.3 Q12 12 15.5 15.3, far M5 11.3 Q12 5.5 19
    // 11.3 (stroke 1.8).
    final arcStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final arcs = Path()
      ..moveTo(8.5 * s, 15.3 * s)
      ..quadraticBezierTo(12 * s, 12 * s, 15.5 * s, 15.3 * s)
      ..moveTo(5 * s, 11.3 * s)
      ..quadraticBezierTo(12 * s, 5.5 * s, 19 * s, 11.3 * s);
    canvas.drawPath(arcs, arcStroke);

    // Dot — circle cx=12 cy=19 r=1.3 (filled).
    final dotFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(12 * s, 19 * s), 1.3 * s, dotFill);

    // Strike — M4 4 L20 20 (stroke 2.2 — thicker than the arcs).
    final strikeStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(Offset(4 * s, 4 * s), Offset(20 * s, 20 * s), strikeStroke);
  }

  @override
  bool shouldRepaint(covariant _WifiSlashGlyphPainter old) => old.color != color;
}
