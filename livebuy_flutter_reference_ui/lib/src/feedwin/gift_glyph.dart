import 'package:flutter/widgets.dart';

// MARK: - GiftGlyph — self-drawn outline gift glyph (design `Icons.gift`)
//
// Design: `design/shared/icons.jsx` `Icons.gift` (24px viewBox, stroke 1.8 default,
// fill none):
//   bow    M12 8.5L7.5 4.5L7.5 8.5Z  M12 8.5L16.5 4.5L16.5 8.5Z   (2 triangular loops)
//   lid    <rect x=4   y=8    width=16 height=3.5 rx=1/>
//   body   <rect x=5.5 y=11.5 width=13 height=8.5 rx=1.5/>
//
// Ported from iOS `GiftGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// GiftGlyph.swift`). Single stroke Path: 2 triangular bow loops (each closed via
// `close()`) + lid rounded rect + body rounded rect.
//
// Distinct from `Icons.giftFill` (the filled variant used unchanged elsewhere by
// this same file's `WinTrophyGlyphPainter` — the win-claim modal's top "always
// gift" success badge in `_giftBadge()`). This is the OUTLINE glyph for the
// pending-product row only; MUST NOT be confused with, or merged into, the top
// badge's glyph implementation — they are two different glyphs with two different
// call sites.
//
// Sole call site: `feedwin/win_claim_sheet.dart`'s `_pendingItemRow()` (replaces
// Material `Icons.redeem`).

/// The self-drawn outline gift glyph (2 bow loops + lid + body, all stroked).
/// [size] is the square edge.
class GiftGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const GiftGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GiftGlyphPainter(color)),
    );
  }
}

class _GiftGlyphPainter extends CustomPainter {
  final Color color;
  _GiftGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      // Left bow loop: (12,8.5) -> (7.5,4.5) -> (7.5,8.5) -> close.
      ..moveTo(12 * s, 8.5 * s)
      ..lineTo(7.5 * s, 4.5 * s)
      ..lineTo(7.5 * s, 8.5 * s)
      ..close()
      // Right bow loop: (12,8.5) -> (16.5,4.5) -> (16.5,8.5) -> close.
      ..moveTo(12 * s, 8.5 * s)
      ..lineTo(16.5 * s, 4.5 * s)
      ..lineTo(16.5 * s, 8.5 * s)
      ..close();

    // Lid: rounded rect x=4 y=8 w=16 h=3.5 rx=1.
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(4 * s, 8 * s, 16 * s, 3.5 * s),
      Radius.circular(1 * s),
    ));
    // Body: rounded rect x=5.5 y=11.5 w=13 h=8.5 rx=1.5.
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(5.5 * s, 11.5 * s, 13 * s, 8.5 * s),
      Radius.circular(1.5 * s),
    ));

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _GiftGlyphPainter old) => old.color != color;
}
