import 'package:flutter/widgets.dart';

// MARK: - MoreGlyph — self-drawn three-dot "more" glyph (design `Icons.more`)
//
// Design: `design/shared/icons.jsx` `Icons.more` (24px viewBox) — three r=1.4 FILLED
// circles at (6,12) / (12,12) / (18,12).
//
// Ported from iOS `MoreGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// MoreGlyph.swift`, rb-ios-icon-parity). Drawn with three `canvas.drawCircle` calls
// (equivalent to, and simpler than, iOS's `Path.addEllipse` + single `fill`).
//
// Flutter parity of iOS `MoreGlyph` (`rb-flutter-icon-parity-operation-rail-batch`)
// — replaces `Icons.more_horiz` at `OperationRailView`'s collapsed `_MorePillButton`
// (the closed-chat finished-live-replay rail's「更多」pill).

/// The self-drawn three-dot "more" glyph. [size] is the square edge.
class MoreGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const MoreGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MoreGlyphPainter(color)),
    );
  }
}

class _MoreGlyphPainter extends CustomPainter {
  final Color color;
  _MoreGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final r = 1.4 * s;
    for (final cx in [6.0, 12.0, 18.0]) {
      canvas.drawCircle(Offset(cx * s, 12 * s), r, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _MoreGlyphPainter old) => old.color != color;
}
