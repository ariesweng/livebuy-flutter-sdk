import 'package:flutter/widgets.dart';

// MARK: - ArrowUpCircleGlyph — self-drawn circled-up-arrow glyph
//                              (design `Icons.arrowUpCircle`)
//
// Design: `design/shared/icons.jsx` `Icons.arrowUpCircle` (24px viewBox, stroke 2,
// fill none):
//   circle  <circle cx=12 cy=12 r=9/>
//   arrow   M12 16V8  M8 12L12 8L16 12   (vertical shaft + up-chevron head)
//
// Ported from iOS `ArrowUpCircleGlyph.swift` (`ios/Sources/LivebuyReferenceUI/
// Glyphs/ArrowUpCircleGlyph.swift`). Circle + shaft + chevron all live in ONE
// `Path` (Dart's `Path.moveTo` starts a new subpath within the same object, same
// as SwiftUI's `Path { p in ... }` builder), painted with a single stroke `Paint`
// — no fill layer, unlike `WifiSlashGlyph`'s multi-layer composition.
//
// Call site (`rb-flutter-icon-parity-error-retry-batch`): `error_screen.dart`
// `.outdated` icon badge (版本過舊錯誤徽章), replacing Material
// `Icons.system_update_alt_rounded`.

/// The self-drawn circled-up-arrow glyph (circle + vertical shaft + chevron
/// head). [size] is the square edge.
class ArrowUpCircleGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const ArrowUpCircleGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ArrowUpCircleGlyphPainter(color)),
    );
  }
}

class _ArrowUpCircleGlyphPainter extends CustomPainter {
  final Color color;
  _ArrowUpCircleGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final r = 9 * s;
    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset(12 * s, 12 * s), radius: r))
      // Vertical shaft — M12 16V8.
      ..moveTo(12 * s, 16 * s)
      ..lineTo(12 * s, 8 * s)
      // Up-chevron head — M8 12L12 8L16 12.
      ..moveTo(8 * s, 12 * s)
      ..lineTo(12 * s, 8 * s)
      ..lineTo(16 * s, 12 * s);

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ArrowUpCircleGlyphPainter old) =>
      old.color != color;
}
