import 'package:flutter/widgets.dart';

// MARK: - SearchGlyph — self-drawn magnifying-glass glyph (design `Icons.search`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-product-list-search-icon-parity).
// Flutter parity of Android `IconGlyphs.kt` `SearchGlyph` (stroked lens circle +
// stroked diagonal handle, `D_SEARCH_HANDLE = "M16 16l4 4"`) and iOS SF Symbol
// `magnifyingglass` (`ProductListView.swift` collapsed/expanded search headers).
// Design `design/shared/icons.jsx`:
//   search: (p) => <Icon {...p}><circle cx="11" cy="11" r="6.5" /><path d="M16 16l4 4" /></Icon>
// — a 24-unit viewBox, default stroke width 1.8, round cap/join (the shared `Icon`
// wrapper's `strokeLinecap="round" strokeLinejoin="round"` default).
//
// Replaces the plain-text emoji `'🔍'` (`TextStyle(fontSize: ...)`) previously drawn
// at both `product_list_sheet.dart` call sites — the collapsed header's leading
// 32×32 search button and the expanded search pill's leading glyph — with a
// deterministic vector, matching the existing `ShareGlyph` / `EqualizerGlyph` /
// `CartFillGlyph` house style (hand-drawn `CustomPainter`, no icon-font dependency,
// stable golden). Identical geometry to Android; iOS's SF Symbol renders the same
// lens+handle silhouette natively.
//
// Pure presentation: only `size` / `color`.

/// The self-drawn magnifying-glass glyph (lens circle + diagonal handle stroke).
/// [size] is the square edge; the design proportions scale by `size / 24`. Used by
/// the product-list sheet header's search button (collapsed + expanded states).
class SearchGlyph extends StatelessWidget {
  /// The glyph box size.
  final double size;

  /// The stroke color.
  final Color color;

  const SearchGlyph({super.key, required this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SearchGlyphPainter(color)),
    );
  }
}

class _SearchGlyphPainter extends CustomPainter {
  final Color color;
  _SearchGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;

    // Lens — stroked circle, center (11,11), radius 6.5 (icons.jsx `circle`).
    canvas.drawCircle(Offset(11 * s, 11 * s), 6.5 * s, stroke);
    // Handle — stroked diagonal line (16,16) -> (20,20) (icons.jsx `M16 16l4 4`).
    canvas.drawLine(Offset(16 * s, 16 * s), Offset(20 * s, 20 * s), stroke);
  }

  @override
  bool shouldRepaint(covariant _SearchGlyphPainter old) => old.color != color;
}
