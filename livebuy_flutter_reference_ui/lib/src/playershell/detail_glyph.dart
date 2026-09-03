import 'package:flutter/widgets.dart';

// MARK: - DetailGlyph — self-drawn list-detail glyph (design `Icons.detail`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-clean-mode-exit-icon-fix). Used by the
// clean-mode exit button (`_CleanModeExitButton` in `player_shell_view.dart`), which previously
// drew the Material `Icons.fullscreen_exit` — a shape that does not match the design's
// list/detail glyph and was explicitly deferred as a Non-Goal by `rb-flutter-gesture-clean-mode-v2`.
//
// Design `design/shared/icons.jsx` `Icons.detail` (~line 48-56), 24-unit viewBox, strokeWidth 1.8:
//   <rect x="3" y="4" width="18" height="16" rx="3" />        frame (stroke)
//   <circle cx="7" cy="9" r="1" fill="currentColor" stroke="none" />   dot 1 (fill)
//   <path d="M10.5 9h7" />                                    line 1 (stroke)
//   <circle cx="7" cy="12" r="1" fill="currentColor" stroke="none" />  dot 2 (fill)
//   <path d="M10.5 12h7" />                                   line 2 (stroke)
//   <circle cx="7" cy="15" r="1" fill="currentColor" stroke="none" />  dot 3 (fill)
//   <path d="M10.5 15h7" />                                   line 3 (stroke)
//
// Geometry mirrors the 24-unit space, scaled by `size/24` (identical convention to
// `ShareGlyph`/`PersonEditGlyph`). No iOS/Android/RN parity file is introduced by this change —
// this is a Flutter-only reference-ui fix; other platforms carry their own equivalent (unfixed)
// deferred item, tracked separately.

/// The self-drawn "list detail" glyph (frame + 3 rows of dot+line). [size] is the square edge.
class DetailGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const DetailGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DetailGlyphPainter(color)),
    );
  }
}

class _DetailGlyphPainter extends CustomPainter {
  final Color color;
  _DetailGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Frame: rounded rect x=3 y=4 w=18 h=16 rx=3 (stroke).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3 * s, 4 * s, 18 * s, 16 * s),
        Radius.circular(3 * s),
      ),
      stroke,
    );

    // Three rows of dot (fill) + line (stroke) at y = 9 / 12 / 15.
    for (final y in const [9.0, 12.0, 15.0]) {
      canvas.drawCircle(Offset(7 * s, y * s), 1 * s, fill);
      canvas.drawLine(
        Offset(10.5 * s, y * s),
        Offset(17.5 * s, y * s),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DetailGlyphPainter old) => old.color != color;
}
