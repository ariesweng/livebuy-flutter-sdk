import 'package:flutter/widgets.dart';

// MARK: - PinFillGlyph — self-drawn round-head pin glyph (design `Icons.pinFill`)
//
// Design: `design/shared/icons.jsx` `Icons.pinFill` (24px viewBox) — a FILL shape:
// circle head r=4.5 at (12,7.5) + straight-line tail polygon
// `M10 11.5 L8 21 L12 18.5 L16 21 L14 11.5 Z`.
//
// Ported from iOS `PinFillGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// PinFillGlyph.swift`, rb-ios-icon-parity). Head drawn with `canvas.drawCircle`; tail
// drawn as a closed `Path` (straight `lineTo` segments only, no curves). Both share
// the same fill `Paint`.
//
// Flutter parity of iOS `PinFillGlyph` / Android `PinFillGlyph`
// (`rb-flutter-icon-parity-operation-rail-batch`) — replaces `Icons.push_pin` at
// `ChatFeedView`'s `_PinnedBanner`（合流聊天 feed 置頂留言橫幅）. **Not** the same
// glyph as the unrelated 「置頂影片」carousel-card kind badge（`video.pin`, design
// R33，語意是輪播卡右上角的置頂影片標記）——that is a DIFFERENT feature and MUST NOT
// reuse or be confused with this file.

/// The self-drawn round-head pin glyph (circle head + straight-line tail). [size] is
/// the square edge.
class PinFillGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const PinFillGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PinFillGlyphPainter(color)),
    );
  }
}

class _PinFillGlyphPainter extends CustomPainter {
  final Color color;
  _PinFillGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Head — circle r=4.5 at (12, 7.5).
    canvas.drawCircle(Offset(12 * s, 7.5 * s), 4.5 * s, fill);

    // Tail — M10 11.5 L8 21 L12 18.5 L16 21 L14 11.5 Z.
    final tail = Path()
      ..moveTo(10 * s, 11.5 * s)
      ..lineTo(8 * s, 21 * s)
      ..lineTo(12 * s, 18.5 * s)
      ..lineTo(16 * s, 21 * s)
      ..lineTo(14 * s, 11.5 * s)
      ..close();
    canvas.drawPath(tail, fill);
  }

  @override
  bool shouldRepaint(covariant _PinFillGlyphPainter old) => old.color != color;
}
