import 'package:flutter/widgets.dart';

// MARK: - BagGlyph — self-drawn fill shopping-bag glyph (design `Icons.bag`)
//
// Design: `design/shared/icons.jsx` `Icons.bag` (24px viewBox) — a FILL shape (not
// stroke). 3 subpaths, SAME winding as icons.jsx, relying on Skia's default
// nonzero-winding fill (`PathFillType.nonZero`, Dart `Path`'s default — same default
// as SwiftUI's `Path.fill(_:style:)`) so subpaths 2/3 render as holes cut into
// subpath 1 (the handle ring + the lower-body ring).
//
// Ported from iOS `BagGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// BagGlyph.swift`, rb-ios-icon-parity, 2026-08-25 redesign). All 3 subpaths live in
// ONE Dart `Path` object (mirrors the single SwiftUI `Path { p in ... }` builder) so
// the nonzero-winding cutouts can form; painted with a single
// `canvas.drawPath(path, fillPaint)` call. `addCurve(to:control1:control2:)` maps to
// `Path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy)`.
//
// Flutter parity of iOS `BagGlyph` / RN `BagGlyph` (`rb-flutter-icon-parity-
// operation-rail-batch`) — replaces `Icons.shopping_bag_outlined` at every 商品袋
// semantic slot in `flutter-reference-ui`: `OperationRailView`'s `_BagButton`,
// `LiveBottomBarView`'s `_BagButton`, and `ChatFeedView`'s `LBActivityTier.purchase`
// activity-line icon slot.

/// The self-drawn fill shopping-bag glyph (silhouette + cutout handle ring). [size]
/// is the square edge.
class BagGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const BagGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BagGlyphPainter(color)),
    );
  }
}

class _BagGlyphPainter extends CustomPainter {
  final Color color;
  _BagGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();

    // Subpath 1 — outer silhouette (body + handle arch cut into the top edge).
    path.moveTo(17.44 * s, 9 * s);
    path.lineTo(15.89 * s, 9 * s);
    path.cubicTo(15.89 * s, 6.85 * s, 14.15 * s, 5.11 * s, 12 * s, 5.11 * s);
    path.cubicTo(9.85 * s, 5.11 * s, 8.11 * s, 6.85 * s, 8.11 * s, 9 * s);
    path.lineTo(6.56 * s, 9 * s);
    path.cubicTo(5.7 * s, 9 * s, 5.01 * s, 9.7 * s, 5.01 * s, 10.56 * s);
    path.lineTo(5 * s, 19.89 * s);
    path.cubicTo(5 * s, 20.74 * s, 5.7 * s, 21.44 * s, 6.56 * s, 21.44 * s);
    path.lineTo(17.44 * s, 21.44 * s);
    path.cubicTo(18.3 * s, 21.44 * s, 19 * s, 20.74 * s, 19 * s, 19.89 * s);
    path.lineTo(19 * s, 10.56 * s);
    path.cubicTo(19 * s, 9.7 * s, 18.3 * s, 9 * s, 17.44 * s, 9 * s);
    path.close();

    // Subpath 2 — handle inner hole (opposing winding → nonzero-fill cutout).
    path.moveTo(12 * s, 6.67 * s);
    path.cubicTo(13.29 * s, 6.67 * s, 14.33 * s, 7.71 * s, 14.33 * s, 9 * s);
    path.lineTo(9.67 * s, 9 * s);
    path.cubicTo(9.67 * s, 7.71 * s, 10.71 * s, 6.67 * s, 12 * s, 6.67 * s);
    path.close();

    // Subpath 3 — lower-body ring hole.
    path.moveTo(12 * s, 14.44 * s);
    path.cubicTo(9.85 * s, 14.44 * s, 8.11 * s, 12.7 * s, 8.11 * s, 10.56 * s);
    path.lineTo(10.4 * s, 10.56 * s);
    path.cubicTo(10.4 * s, 11.469 * s, 11.114 * s, 12.2 * s, 12 * s, 12.2 * s);
    path.cubicTo(12.886 * s, 12.2 * s, 13.6 * s, 11.469 * s, 13.6 * s, 10.56 * s);
    path.lineTo(15.89 * s, 10.56 * s);
    path.cubicTo(15.89 * s, 12.7 * s, 14.15 * s, 14.44 * s, 12 * s, 14.44 * s);
    path.close();

    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _BagGlyphPainter old) => old.color != color;
}
