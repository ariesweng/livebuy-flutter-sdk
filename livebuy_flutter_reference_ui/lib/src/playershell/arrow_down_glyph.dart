import 'package:flutter/widgets.dart';

// MARK: - ArrowDownGlyph — self-drawn simple down-arrow glyph (design `Icons.arrowDown`)
//
// Design: `design/shared/icons.jsx` `Icons.arrowDown` (24px viewBox, stroke, fill
// none) — single `d`:
//   M12 4V20M6 14L12 20L18 14   (vertical shaft + down-chevron head, two straight
//                                 subpaths, no curves)
//
// Ported from iOS `ArrowDownGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// ArrowDownGlyph.swift`, rb-ios-icon-parity) / Android `IconGlyphs.kt`'s
// `ArrowDownGlyph` (`android/livebuy-reference-ui/.../IconGlyphs.kt`,
// rb-android-icon-parity). Stroke technique and scale factor mirror the existing
// stroke-based glyph `arrow_clockwise_glyph.dart` (`s = size.shortestSide / 24.0`,
// `strokeWidth = 2 * s`, round cap/join) — aligned with Android's `strokePath(p,
// color, 2f)` and the design's global default stroke width 2, not iOS's
// implementation-local `1.8 * s` (see rb-flutter-icon-parity-chat-returntolatest-arrow
// design.md Decision D2 for the rationale on this small, pre-existing cross-platform
// difference).
//
// Replaces the bare Unicode "↓" glyph previously embedded inline in the
// "回到最新訊息" pill's `Text` string at `ChatFeedView`'s `_ScrollableChatFeed`
// (rb-flutter-icon-parity-chat-returntolatest-arrow) — its only call site.
//
// Pure presentation: only `size` / `color`.

/// The self-drawn simple down-arrow glyph (vertical shaft + chevron head). [size]
/// is the square edge.
class ArrowDownGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const ArrowDownGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ArrowDownGlyphPainter(color)),
    );
  }
}

class _ArrowDownGlyphPainter extends CustomPainter {
  final Color color;
  _ArrowDownGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      // Shaft — M12 4 V20.
      ..moveTo(12 * s, 4 * s)
      ..lineTo(12 * s, 20 * s)
      // Chevron head — M6 14 L12 20 L18 14.
      ..moveTo(6 * s, 14 * s)
      ..lineTo(12 * s, 20 * s)
      ..lineTo(18 * s, 14 * s);

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ArrowDownGlyphPainter old) => old.color != color;
}
