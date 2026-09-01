import 'package:flutter/widgets.dart';

// MARK: - EqualizerGlyph — hand-drawn 3-bar equalizer (design「介紹中」mark)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-product-list-introducing-banner).
// Flutter parity of iOS `Glyphs/EqualizerGlyph.swift` / Android `IconGlyphs.kt`
// `EqualizerGlyph` / RN `productsheets/EqualizerGlyph.tsx`. Design
// `design/templates/minimal/live-chrome.jsx` `LBLivePinnedCard` +
// `sdk-components.jsx` `LBPProductRow` introBadge —
//   <rect x3   y14 w3 h7  rx0.5/>
//   <rect x10.5 y9 w3 h12 rx0.5/>
//   <rect x18  y4  w3 h17 rx0.5/>   (24-unit viewBox, fill)
//
// Three bottom-aligned, ascending-height filled bars — the「介紹中」(now-introducing)
// vocabulary shared by the LIVE pinned card tag and the product-list banner. Drawn
// with `CustomPaint` (as with `ShareGlyph`) so it does not depend on any icon font
// for a stable golden, scaled by `size / 24`. Identical geometry to iOS / Android / RN.
//
// Pure presentation: only `size` / `color`.

/// The design's 3-bar equalizer mark, hand-drawn to match the「介紹中」badge.
/// [size] is the square edge; the design proportions scale by `size / 24`. Used by
/// the product-list introducing banner (white) and the mini-cart「介紹中」tag (accent).
class EqualizerGlyph extends StatelessWidget {
  /// The glyph box size.
  final double size;

  /// The fill color.
  final Color color;

  const EqualizerGlyph({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EqualizerGlyphPainter(color)),
    );
  }
}

class _EqualizerGlyphPainter extends CustomPainter {
  final Color color;
  _EqualizerGlyphPainter(this.color);

  // (x, y, w, h) per the design svg — all bars bottom at y21.
  static const List<List<double>> _bars = [
    [3, 14, 3, 7],
    [10.5, 9, 3, 12],
    [18, 4, 3, 17],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final radius = Radius.circular(0.5 * s);
    for (final b in _bars) {
      final rect = Rect.fromLTWH(b[0] * s, b[1] * s, b[2] * s, b[3] * s);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerGlyphPainter old) => old.color != color;
}
