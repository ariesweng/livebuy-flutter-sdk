import 'package:flutter/widgets.dart';

// MARK: - HotGlyph — self-drawn FontAwesome-style fire glyph (design `Icons.hot`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-product-row-number-badge, design R35).
// Design: `design/shared/icons.jsx` `Icons.hot` — `viewBox 0 0 448 512`:
//
//   M323.56 51.2c-20.8 19.3-39.58 39.59-56.22 59.97C240.08 73.62 206.28 35.53 168 0 69.74 91.17
//   0 209.96 0 281.6 0 408.85 100.29 512 224 512s224-103.15 224-230.4c0-53.27-51.98-163.14
//   -124.44-230.4zm-19.47 340.65C282.43 407.01 255.72 416 226.86 416 154.71 416 96 368.26 96
//   290.75c0-38.61 24.31-72.63 72.79-130.75 6.93 7.98 98.83 125.34 98.83 125.34l58.63-66.88
//   c4.14 6.85 7.91 13.55 11.27 19.97 27.35 52.19 15.81 118.97-33.43 153.42z
//
// This path is entirely `c`/`C`/`s`/`m`/`l`/`z` commands — it contains NO `a`/`A` (elliptical
// arc), so `design/contract/icon-authoring.md` rule 1 (arc must be converted to cubic bezier and
// backfilled as the authoritative coordinates) does not apply here: the path is translated
// verbatim (relative commands resolved to absolute, per SVG semantics) into Flutter `Path`
// `moveTo`/`cubicTo`/`lineTo`/`close` calls, below. Both subpaths' final segment closes exactly
// onto their own `moveTo` start point (verified by hand before writing this file) — an
// arithmetic consistency check that the relative→absolute conversion was done correctly.
//
// Two subpaths: the outer flame silhouette, and an inner "flame lick" cutout fully contained
// within it (no self-intersection). `Path.fillType = PathFillType.evenOdd` is used instead of
// relying on the SVG's default `nonzero` fill-rule + the two subpaths' relative winding
// direction — evenOdd punches a hole wherever a fully-contained inner subpath overlaps the
// outer one, REGARDLESS of winding direction, so correctness here does not depend on having
// preserved the original SVG's winding sense through the manual coordinate conversion.
//
// `viewBox` is NOT square (448×512, unlike the 24-unit icons elsewhere in this package), so —
// mirroring `equalizer_glyph.dart` / `gift_glyph.dart` / `cart_fill_glyph.dart`'s
// `size.shortestSide`-based scaling convention — this scales by `size.shortestSide / 512.0` and
// horizontally centers the (narrower) rendered width within [size].

/// The self-drawn fire glyph (design `Icons.hot`) — a filled flame silhouette with an inner
/// "flame lick" cutout. [size] is the square edge; the (non-square) 448×512 viewBox content is
/// scaled to fit [size]'s shortest side and horizontally centered.
class HotGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const HotGlyph({super.key, required this.color, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HotGlyphPainter(color)),
    );
  }
}

class _HotGlyphPainter extends CustomPainter {
  final Color color;
  _HotGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 512.0;
    final dx = (size.width - 448 * s) / 2;
    canvas.save();
    canvas.translate(dx, 0);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()..fillType = PathFillType.evenOdd;

    // Outer flame silhouette.
    path
      ..moveTo(323.56 * s, 51.2 * s)
      ..cubicTo(302.76 * s, 70.5 * s, 283.98 * s, 90.79 * s, 267.34 * s, 111.17 * s)
      ..cubicTo(240.08 * s, 73.62 * s, 206.28 * s, 35.53 * s, 168 * s, 0 * s)
      ..cubicTo(69.74 * s, 91.17 * s, 0 * s, 209.96 * s, 0 * s, 281.6 * s)
      ..cubicTo(0 * s, 408.85 * s, 100.29 * s, 512 * s, 224 * s, 512 * s)
      ..cubicTo(347.71 * s, 512 * s, 448 * s, 408.85 * s, 448 * s, 281.6 * s)
      ..cubicTo(448 * s, 228.33 * s, 396.02 * s, 118.46 * s, 323.56 * s, 51.2 * s)
      ..close();

    // Inner "flame lick" cutout.
    path
      ..moveTo(304.09 * s, 391.85 * s)
      ..cubicTo(282.43 * s, 407.01 * s, 255.72 * s, 416 * s, 226.86 * s, 416 * s)
      ..cubicTo(154.71 * s, 416 * s, 96 * s, 368.26 * s, 96 * s, 290.75 * s)
      ..cubicTo(96 * s, 252.14 * s, 120.31 * s, 218.12 * s, 168.79 * s, 160 * s)
      ..cubicTo(175.72 * s, 167.98 * s, 267.62 * s, 285.34 * s, 267.62 * s, 285.34 * s)
      ..lineTo(326.25 * s, 218.46 * s)
      ..cubicTo(330.39 * s, 225.31 * s, 334.16 * s, 232.01 * s, 337.52 * s, 238.43 * s)
      ..cubicTo(364.87 * s, 290.62 * s, 353.33 * s, 357.4 * s, 304.09 * s, 391.85 * s)
      ..close();

    canvas.drawPath(path, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HotGlyphPainter old) => old.color != color;
}
