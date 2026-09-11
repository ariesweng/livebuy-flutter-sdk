import 'package:flutter/widgets.dart';

// MARK: - MegaphoneGlyph — self-drawn FontAwesome bullhorn glyph (design `Icons.megaphone`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-live-announce-bullhorn-icon).
// Design: `design/shared/icons.jsx` `Icons.megaphone` — `viewBox 0 0 576 512`, Font Awesome
// bullhorn shape (2026-09-09 design resync commit `904654d5a`, replacing an earlier hand-drawn
// flag/pennant glyph). Used inside `LiveOverlayChromeView._announceBanner()`'s red `#F03246`
// icon badge (`LBLiveAnnounce`), replacing Material `Icons.campaign`.
//
//   M576 240c0-23.63-12.95-44.04-32-55.12V32.01C544 23.26 537.02 0 512 0c-7.12 0-14.19 2.38
//   -19.98 7.02l-85.03 68.03C364.28 109.19 310.66 128 256 128H64c-35.35 0-64 28.65-64 64v96
//   c0 35.35 28.65 64 64 64h33.7c-1.39 10.48-2.18 21.14-2.18 32 0 39.77 9.26 77.35 25.56 110.94
//   5.19 10.69 16.52 17.06 28.4 17.06h74.28c26.05 0 41.69-29.84 25.9-50.56-16.4-21.52-26.15
//   -48.36-26.15-77.44 0-11.11 1.62-21.79 4.41-32H256c54.66 0 108.28 18.81 150.98 52.95l85.03
//   68.03C497.68 477.52 504.73 479.99 511.99 480c24.92 0 32-22.78 32-32V295.13
//   C563.05 284.04 576 263.63 576 240zm-96 141.42l-33.05-26.44C392.95 311.78 325.12 288 256 288
//   v-96c69.12 0 136.95-23.78 190.95-66.98L480 98.58v282.84z
//
// The upstream SVG contains exactly ONE elliptical-arc command (originally
// `a32.023 32.023 0 0 0 19.98 7.02`), already converted per `design/contract/icon-authoring.md`
// rule 1 into the equivalent cubic bezier (`C497.68 477.52 504.73 479.99 511.99 480`) and
// backfilled as the authoritative `icons.jsx` coordinates (see that file's inline comment) — so
// the path consumed here is already pure M/L/C/Z, zero arcs; nothing further to convert.
//
// Two subpaths: the outer bullhorn silhouette (bell + handle + grip), and the mouthpiece
// "sound hole" cutout at the narrow end — fully contained within the outer silhouette, no
// self-intersection. `Path.fillType = PathFillType.evenOdd` punches the hole regardless of
// winding direction (mirrors `hot_glyph.dart` / `cart_fill_glyph.dart`'s evenOdd convention for
// a two-subpath fill+cutout shape).
//
// `viewBox` is 576×512 — WIDER than tall (unlike `hot_glyph.dart`'s 448×512, which is taller
// than wide), so this scales by `size.shortestSide / 576.0` and VERTICALLY centers the
// (shorter) rendered height within [size] (padding lands on `dy`, not `dx`).

/// The self-drawn FontAwesome bullhorn glyph (design `Icons.megaphone`) — a filled bullhorn
/// silhouette with a mouthpiece cutout. [size] is the square edge; the (non-square) 576×512
/// viewBox content is scaled to fit [size]'s shortest side and vertically centered.
class MegaphoneGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const MegaphoneGlyph({super.key, required this.color, this.size = 13});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MegaphoneGlyphPainter(color)),
    );
  }
}

class _MegaphoneGlyphPainter extends CustomPainter {
  final Color color;
  _MegaphoneGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 576.0;
    final dy = (size.height - 512 * s) / 2;
    canvas.save();
    canvas.translate(0, dy);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()..fillType = PathFillType.evenOdd;

    // Outer bullhorn silhouette.
    path
      ..moveTo(576 * s, 240 * s)
      ..cubicTo(576 * s, 216.37 * s, 563.05 * s, 195.96 * s, 544 * s, 184.88 * s)
      ..lineTo(544 * s, 32.01 * s)
      ..cubicTo(544 * s, 23.26 * s, 537.02 * s, 0 * s, 512 * s, 0 * s)
      ..cubicTo(504.88 * s, 0 * s, 497.81 * s, 2.38 * s, 492.02 * s, 7.02 * s)
      ..lineTo(406.99 * s, 75.05 * s)
      ..cubicTo(364.28 * s, 109.19 * s, 310.66 * s, 128 * s, 256 * s, 128 * s)
      ..lineTo(64 * s, 128 * s)
      ..cubicTo(28.65 * s, 128 * s, 0 * s, 156.65 * s, 0 * s, 192 * s)
      ..lineTo(0 * s, 288 * s)
      ..cubicTo(0 * s, 323.35 * s, 28.65 * s, 352 * s, 64 * s, 352 * s)
      ..lineTo(97.7 * s, 352 * s)
      ..cubicTo(96.31 * s, 362.48 * s, 95.52 * s, 373.14 * s, 95.52 * s, 384 * s)
      ..cubicTo(95.52 * s, 423.77 * s, 104.78 * s, 461.35 * s, 121.08 * s, 494.94 * s)
      ..cubicTo(126.27 * s, 505.63 * s, 137.6 * s, 512 * s, 149.48 * s, 512 * s)
      ..lineTo(223.76 * s, 512 * s)
      ..cubicTo(249.81 * s, 512 * s, 265.45 * s, 482.16 * s, 249.66 * s, 461.44 * s)
      ..cubicTo(233.26 * s, 439.92 * s, 223.51 * s, 413.08 * s, 223.51 * s, 384 * s)
      ..cubicTo(223.51 * s, 372.89 * s, 225.13 * s, 362.21 * s, 227.92 * s, 352 * s)
      ..lineTo(256 * s, 352 * s)
      ..cubicTo(310.66 * s, 352 * s, 364.28 * s, 370.81 * s, 406.98 * s, 404.95 * s)
      ..lineTo(492.01 * s, 472.98 * s)
      ..cubicTo(497.68 * s, 477.52 * s, 504.73 * s, 479.99 * s, 511.99 * s, 480 * s)
      ..cubicTo(536.91 * s, 480 * s, 543.99 * s, 457.22 * s, 543.99 * s, 448 * s)
      ..lineTo(543.99 * s, 295.13 * s)
      ..cubicTo(563.05 * s, 284.04 * s, 576 * s, 263.63 * s, 576 * s, 240 * s)
      ..close();

    // Mouthpiece "sound hole" cutout.
    path
      ..moveTo(480 * s, 381.42 * s)
      ..lineTo(446.95 * s, 354.98 * s)
      ..cubicTo(392.95 * s, 311.78 * s, 325.12 * s, 288 * s, 256 * s, 288 * s)
      ..lineTo(256 * s, 192 * s)
      ..cubicTo(325.12 * s, 192 * s, 392.95 * s, 168.22 * s, 446.95 * s, 125.02 * s)
      ..lineTo(480 * s, 98.58 * s)
      ..lineTo(480 * s, 381.42 * s)
      ..close();

    canvas.drawPath(path, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MegaphoneGlyphPainter old) => old.color != color;
}
