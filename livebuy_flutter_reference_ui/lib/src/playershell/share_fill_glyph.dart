import 'package:flutter/widgets.dart';

// MARK: - ShareFillGlyph — self-drawn FILLED share glyph (design `Icons.shareFill`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-live-more-sheet-share-fill-icon).
//
// Design `design/shared/icons.jsx` `Icons.shareFill` (`shareFill:` key, ~line 25), 24-unit
// viewBox, `stroke="none"`, `fill=currentColor`:
//   <circle cx="6"  cy="12" r="3" />
//   <circle cx="18" cy="6"  r="3" />
//   <circle cx="18" cy="18" r="3" />
//   <path d="M8.2 10.6l7.8-3.9 1 2-7.8 3.9zM8.2 13.4l7.8 3.9 1-2-7.8-3.9z" />
//
// A FILLED variant of the existing STROKED `ShareGlyph` (`Icons.share`, used by
// `operation_rail.dart`'s side rail and `live_bottom_bar_view.dart`'s LIVE bottom bar — both
// remain unchanged by this change, they align to the stroked design token). This filled glyph
// is what `_RailMoreMenuSheet`'s (the「更多」sheet, `player_shell_view.dart`) 分享 slot uses —
// mirrors iOS `ShareFillGlyph.swift` (`rb-ios-live-replay-more-menu-and-video-info-live-copy`).
//
// The SVG path uses relative `l` line commands forming two closed parallelogram bars. Hand-
// expanded to absolute coordinates (24-unit space, cross-checked against the iOS parity file):
//   bar 1: (8.2,10.6) -> (16.0,6.7) -> (17.0,8.7) -> (9.2,12.6) -> close
//   bar 2: (8.2,13.4) -> (16.0,17.3) -> (17.0,15.3) -> (9.2,11.4) -> close
//
// Three filled r=3 nodes connected by two filled parallelogram bars (straight lines only, no
// arcs). Geometry scales by `size / 24` (identical convention to `ShareGlyph`/`CcGlyph`).

/// The design's filled three-node share glyph (rounded fill nodes + two filled connecting
/// bars). [size] is the square edge.
class ShareFillGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const ShareFillGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShareFillGlyphPainter(color)),
    );
  }
}

class _ShareFillGlyphPainter extends CustomPainter {
  final Color color;
  _ShareFillGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Three filled nodes at (6,12) / (18,6) / (18,18), r=3.
    for (final node in const [Offset(6, 12), Offset(18, 6), Offset(18, 18)]) {
      canvas.drawCircle(Offset(node.dx * s, node.dy * s), 3 * s, fill);
    }

    // Connecting bar 1: (8.2,10.6) -> (16.0,6.7) -> (17.0,8.7) -> (9.2,12.6) -> close.
    final bar1 = Path()
      ..moveTo(8.2 * s, 10.6 * s)
      ..lineTo(16.0 * s, 6.7 * s)
      ..lineTo(17.0 * s, 8.7 * s)
      ..lineTo(9.2 * s, 12.6 * s)
      ..close();
    canvas.drawPath(bar1, fill);

    // Connecting bar 2: (8.2,13.4) -> (16.0,17.3) -> (17.0,15.3) -> (9.2,11.4) -> close.
    final bar2 = Path()
      ..moveTo(8.2 * s, 13.4 * s)
      ..lineTo(16.0 * s, 17.3 * s)
      ..lineTo(17.0 * s, 15.3 * s)
      ..lineTo(9.2 * s, 11.4 * s)
      ..close();
    canvas.drawPath(bar2, fill);
  }

  @override
  bool shouldRepaint(covariant _ShareFillGlyphPainter old) => old.color != color;
}
