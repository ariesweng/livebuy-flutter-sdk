import 'package:flutter/widgets.dart';

// MARK: - CartFillGlyph — self-drawn filled cart glyph (design `Icons.cartFill`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-icon-parity-cart-cta-retirement).
// Flutter parity of iOS `Glyphs/CartFillGlyph.swift` and Android `IconGlyphs.kt`
// `CartFillGlyph` — both already migrated as part of the 2026-08-25 icon redesign.
// Replaces `ShopBagGlyph` (retired, deleted) at the「查看購物車」CTA footer
// (`LBPCartCTA`, `product_list_sheet.dart`'s `_CartCTAFooter`) — the `bag` silhouette
// wasn't legible at the footer's small render size, design now specifies `cartFill`.
//
// Drawn in a 24-unit space (scaled by `s = size/24`), faithfully tracing
// `design/shared/icons.jsx` `Icons.cartFill`:
//   basket  M6 8L20 8L18 16L7 16Z                    (filled trapezoid, no stroke)
//   handle  M3 5h2l1.6 3                              (stroked hook, strokeWidth 2)
//   wheels  circle(cx=9 cy=20 r=1.6) + circle(cx=17 cy=20 r=1.6)   (filled)
// Basket body + both wheels share ONE fill Path (nonzero winding); the hook handle is a
// SEPARATE stroke Path. Fill and stroke share the same [color] (no separate accents).

/// The self-drawn filled cart glyph (basket trapezoid + hook handle + 2 wheels).
/// [size] is the square edge (the design uses ~18–20, matching the retired `ShopBagGlyph`
/// default so the existing call site's rendered size is unchanged).
class CartFillGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const CartFillGlyph({super.key, required this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CartFillGlyphPainter(color)),
    );
  }
}

class _CartFillGlyphPainter extends CustomPainter {
  final Color color;
  _CartFillGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;

    // Basket body (trapezoid) + 2 wheels — ONE combined fill Path.
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final basketAndWheels = Path()
      ..moveTo(6 * s, 8 * s)
      ..lineTo(20 * s, 8 * s)
      ..lineTo(18 * s, 16 * s)
      ..lineTo(7 * s, 16 * s)
      ..close();
    const wheelRadius = 1.6;
    for (final cx in const [9.0, 17.0]) {
      basketAndWheels.addOval(Rect.fromCircle(
        center: Offset(cx * s, 20 * s),
        radius: wheelRadius * s,
      ));
    }
    canvas.drawPath(basketAndWheels, fill);

    // Hook handle — SEPARATE stroke Path.
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final handle = Path()
      ..moveTo(3 * s, 5 * s)
      ..lineTo(5 * s, 5 * s)
      ..lineTo(6.6 * s, 8 * s);
    canvas.drawPath(handle, stroke);
  }

  @override
  bool shouldRepaint(covariant _CartFillGlyphPainter old) => old.color != color;
}
