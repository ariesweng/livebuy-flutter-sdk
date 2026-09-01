import 'package:flutter/widgets.dart';

// MARK: - ShopBagGlyph — self-drawn outline shopping-bag glyph (design `Icons.shopBag`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-cart-cta-shopbag-glyph).
// Flutter parity of iOS / Android `ShopBagGlyph` (Android `IconGlyphs.kt` D_SHOP_BAG_*) and RN
// `ShopBagGlyph`. Replaces the prior 🛍 emoji in the cart 摘要 footer (`LBPCartCTA`「查看購物車」).
//
// Drawn in a 24-unit space (scaled by `s = size/24`), faithfully tracing `design/shared/icons.jsx`
// `shopBag` (stroked, white over the accent footer):
//   body   M6 8h12l-1 12a2 2 0 01-2 2H9a2 2 0 01-2-2L6 8z  → bag outline with rounded bottom corners
//   handle M9 8V6a3 3 0 016 0v2                            → ∩ ring: 2 sides + top semicircle (r=3)
//   mouth  M9 12h6                                         → horizontal line at y=12
// The FULL handle ring + mouth line is exactly what distinguishes `shopBag` from the simple `bag`.

/// The self-drawn outline shopping-bag glyph. [size] is the square edge (the design uses ~18–20).
class ShopBagGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const ShopBagGlyph({super.key, required this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShopBagGlyphPainter(color)),
    );
  }
}

class _ShopBagGlyphPainter extends CustomPainter {
  final Color color;
  _ShopBagGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    // Stroke bumped 1.8 → 2.3 to visually compensate for iOS SF Symbol `.semibold`/`.bold`
    // rendering more thickly than this literal Canvas trace (rb-bag-glyph-stroke-weight,
    // same value across RN/Android/Flutter for cross-platform consistency).
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Bag body — M6 8 h12 l-1 12 a2 2 0 01-2 2 H9 a2 2 0 01-2 -2 L6 8 z
    final body = Path()
      ..moveTo(6 * s, 8 * s)
      ..lineTo(18 * s, 8 * s)
      ..lineTo(17 * s, 20 * s)
      ..arcToPoint(Offset(15 * s, 22 * s), radius: Radius.circular(2 * s), clockwise: true)
      ..lineTo(9 * s, 22 * s)
      ..arcToPoint(Offset(7 * s, 20 * s), radius: Radius.circular(2 * s), clockwise: true)
      ..lineTo(6 * s, 8 * s)
      ..close();

    // Handle ∩ ring — M9 8 V6 a3 3 0 016 0 v2
    final handle = Path()
      ..moveTo(9 * s, 8 * s)
      ..lineTo(9 * s, 6 * s)
      ..arcToPoint(Offset(15 * s, 6 * s), radius: Radius.circular(3 * s), clockwise: true)
      ..lineTo(15 * s, 8 * s);

    // Mouth line — M9 12 h6
    final mouth = Path()
      ..moveTo(9 * s, 12 * s)
      ..lineTo(15 * s, 12 * s);

    canvas.drawPath(body, stroke);
    canvas.drawPath(handle, stroke);
    canvas.drawPath(mouth, stroke);
  }

  @override
  bool shouldRepaint(covariant _ShopBagGlyphPainter old) => old.color != color;
}
