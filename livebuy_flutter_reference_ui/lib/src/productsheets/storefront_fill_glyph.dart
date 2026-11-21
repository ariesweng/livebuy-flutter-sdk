import 'package:flutter/widgets.dart';

// MARK: - StorefrontFillGlyph — self-drawn filled storefront (design `Icons.storefrontFill`)
//
// Spec: `reference-ui-rendering/spec.md`（rb-flutter-flash-sale-bid，搶購得標視窗（Flutter））.
// Flutter parity of iOS `Glyphs/StorefrontFillGlyph.swift` / Android `IconGlyphs.kt`
// `StorefrontFillGlyph` / RN `StorefrontFillGlyph.tsx`. Call site: the 30pt accent glyph that always
// sits under the merchant logo in the「恭喜搶購成功」popup (`moments.jsx` `LBBidWonModal`).
//
// Drawn in a 24-unit space (scaled by `s = size/24`), tracing `design/shared/icons.jsx`
// `Icons.storefrontFill` (both subpaths filled, no stroke). No arc (`icon-authoring.md` rule 1 does
// not apply); relative `h` / `l` / `c` and smooth `S` commands are resolved to absolute coordinates
// below (each `S` first control point = the previous segment's second control point reflected
// about the current point):
//   awning  M4 3h16l2 5c0 1.4-1.1 2.5-2.5 2.5S17 9.4 17 8c0 1.4-1.1 2.5-2.5 2.5S12 9.4 12 8
//           c0 1.4-1.1 2.5-2.5 2.5S7 9.4 7 8c0 1.4-1.1 2.5-2.5 2.5S2 9.4 2 8l2-5z
//   body    M4.5 12h15v9.5h-5.5v-5.5h-4v5.5h-5.5z   (door notch cut into the body outline)

/// The self-drawn filled storefront glyph (scalloped awning + body with a door notch).
/// [size] is the square edge.
class StorefrontFillGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const StorefrontFillGlyph({super.key, required this.color, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _StorefrontFillGlyphPainter(color)),
    );
  }
}

class _StorefrontFillGlyphPainter extends CustomPainter {
  final Color color;
  _StorefrontFillGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final awning = Path()
      ..moveTo(4 * s, 3 * s)
      ..lineTo(20 * s, 3 * s)
      ..lineTo(22 * s, 8 * s)
      ..cubicTo(22 * s, 9.4 * s, 20.9 * s, 10.5 * s, 19.5 * s, 10.5 * s)
      ..cubicTo(18.1 * s, 10.5 * s, 17 * s, 9.4 * s, 17 * s, 8 * s)
      ..cubicTo(17 * s, 9.4 * s, 15.9 * s, 10.5 * s, 14.5 * s, 10.5 * s)
      ..cubicTo(13.1 * s, 10.5 * s, 12 * s, 9.4 * s, 12 * s, 8 * s)
      ..cubicTo(12 * s, 9.4 * s, 10.9 * s, 10.5 * s, 9.5 * s, 10.5 * s)
      ..cubicTo(8.1 * s, 10.5 * s, 7 * s, 9.4 * s, 7 * s, 8 * s)
      ..cubicTo(7 * s, 9.4 * s, 5.9 * s, 10.5 * s, 4.5 * s, 10.5 * s)
      ..cubicTo(3.1 * s, 10.5 * s, 2 * s, 9.4 * s, 2 * s, 8 * s)
      ..lineTo(4 * s, 3 * s)
      ..close();
    canvas.drawPath(awning, fill);

    final body = Path()
      ..moveTo(4.5 * s, 12 * s)
      ..lineTo(19.5 * s, 12 * s)
      ..lineTo(19.5 * s, 21.5 * s)
      ..lineTo(14 * s, 21.5 * s)
      ..lineTo(14 * s, 16 * s)
      ..lineTo(10 * s, 16 * s)
      ..lineTo(10 * s, 21.5 * s)
      ..lineTo(4.5 * s, 21.5 * s)
      ..close();
    canvas.drawPath(body, fill);
  }

  @override
  bool shouldRepaint(covariant _StorefrontFillGlyphPainter old) => old.color != color;
}
