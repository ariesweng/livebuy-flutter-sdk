import 'package:flutter/widgets.dart';

// MARK: - CcGlyph — self-drawn three-state subtitle/CC glyph (design R42: `Icons.ccOn` /
// `Icons.ccOff` / `Icons.ccUnavailable`)
//
// Spec: `reference-ui-rendering/spec.md` (`rb-flutter-cc-icon-availability-redesign`). Used by the
// VOD side-rail subtitle pill (`operation_rail.dart`'s `_CcPillButton`) and the LIVE
// `isFinishedLiveReplay` bottom-bar CC toggle (`live_bottom_bar_view.dart`'s `_CcTrailingButton`).
//
// R42 REPLACES the prior single hand-drawn double-"C" badge (`rb-flutter-cc-icon-design-align`)
// with THREE distinct fill glyphs, all cubic-bezier/line only (no arc commands, per
// `design/contract/icon-authoring.md` rule 1 — nothing to convert):
//
//   [CcGlyphState.on]          `Icons.ccOn`  — 512×512 viewBox, FontAwesome "closed-captioning"
//                               SOLID glyph: a filled rounded-square badge with the two "C" shapes
//                               cut out as negative-space holes (`PathFillType.evenOdd`, 3
//                               subpaths: badge outline + left-C hole + right-C hole).
//   [CcGlyphState.off]         `Icons.ccOff` — 512×512 viewBox, FontAwesome "closed-captioning"
//                               REGULAR glyph: a hollow badge FRAME (outer + inner rounded-rect
//                               outline forming a border ring) with the two "C" shapes filled
//                               solid inside the hollow middle (`PathFillType.evenOdd`, 4
//                               subpaths: outer frame + inner frame + left-C + right-C — the outer
//                               subpath is byte-identical to `on`'s badge outline).
//   [CcGlyphState.unavailable] `Icons.ccUnavailable` — 24×22 viewBox (NON-square, 18:16 aspect at
//                               the design's default render size — `icons.jsx`'s `Icon` base
//                               gained a `width`/`height` override for this), fixed fill
//                               `#A0A0A0` regardless of the [CcGlyph.color] argument (design
//                               `stroke={0} fill="#A0A0A0"`, ignores `p.color`) — 4 subpaths
//                               (outer frame + inner frame forming a border ring, + two
//                               unavailable-source icon shapes).
//
// Coordinates are the EXACT `design/shared/icons.jsx` path data (2026-09-10 R42 sync), mechanically
// transcribed SVG-command-by-command into absolute-coordinate Dart `Path` calls (M/L/H/V/C, with
// relative lowercase variants resolved to absolute) — same transcription discipline as
// `feedwin/gift_glyph.dart` / `megaphone_glyph.dart`. `PathFillType.evenOdd` reproduces the
// SVG holes/frames regardless of each subpath's winding direction (mirrors `megaphone_glyph.dart`'s
// own reasoning for its mouthpiece cutout — the technique generalizes to N nested subpaths, not
// just one hole).

/// The subtitle (CC) icon's three states.
enum CcGlyphState {
  /// Captions are available AND currently on — filled `Icons.ccOn` badge.
  on,

  /// Captions are available but currently off — outline `Icons.ccOff` badge.
  off,

  /// No caption source exists for this video — fixed-grey `Icons.ccUnavailable` (non-square,
  /// ignores [CcGlyph.color]). Tapping this state does NOT toggle captions — the caller (
  /// `_CcPillButton` / `_CcTrailingButton`) routes the tap to a short-lived tooltip instead.
  unavailable,
}

/// The self-drawn three-state subtitle/CC glyph (design R42 `Icons.ccOn`/`ccOff`/`ccUnavailable`).
/// [size] is the square edge for [CcGlyphState.on] / [CcGlyphState.off]; for
/// [CcGlyphState.unavailable] it is the WIDTH basis — the rendered box keeps the design's
/// non-square 18:16 aspect (`height = size * 16 / 18`), NOT forced square.
class CcGlyph extends StatelessWidget {
  final CcGlyphState state;

  /// Fill color for [CcGlyphState.on] / [CcGlyphState.off]. IGNORED for
  /// [CcGlyphState.unavailable], which always paints the fixed `#A0A0A0` (design-literal, not
  /// theme-tintable).
  final Color color;

  final double size;

  const CcGlyph({
    super.key,
    required this.state,
    this.color = const Color(0xFFFFFFFF),
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final height = state == CcGlyphState.unavailable ? size * 16 / 18 : size;
    return SizedBox(
      width: size,
      height: height,
      child: CustomPaint(painter: _CcGlyphPainter(state: state, color: color)),
    );
  }
}

/// The `ccUnavailable` glyph's fixed fill — design-literal, MUST NOT be overridden by
/// [CcGlyph.color] (parity `icons.jsx` `ccUnavailable: (p) => <Icon {...p} stroke={0}
/// fill="#A0A0A0" .../>`, which ignores `p.color`).
const Color _ccUnavailableColor = Color(0xFFA0A0A0);

class _CcGlyphPainter extends CustomPainter {
  final CcGlyphState state;
  final Color color;

  _CcGlyphPainter({required this.state, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    switch (state) {
      case CcGlyphState.on:
        final s = size.shortestSide / 512.0;
        _paint(canvas, _ccOnPath(s), color);
      case CcGlyphState.off:
        final s = size.shortestSide / 512.0;
        _paint(canvas, _ccOffPath(s), color);
      case CcGlyphState.unavailable:
        // Non-uniform sx/sy — the 24×22 viewBox is deliberately NOT squared (see class doc).
        final sx = size.width / 24.0;
        final sy = size.height / 22.0;
        _paint(canvas, _ccUnavailablePath(sx, sy), _ccUnavailableColor);
    }
  }

  void _paint(Canvas canvas, Path path, Color fillColor) {
    canvas.drawPath(path, Paint()..color = fillColor..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _CcGlyphPainter old) =>
      old.state != state || old.color != color;
}

// MARK: - Path builders (design `icons.jsx` `ccOn` / `ccOff` / `ccUnavailable`, 2026-09-10 R42)

/// The outer badge outline — byte-identical subpath shared by [_ccOnPath] (as its only frame
/// subpath, badge is solid) and [_ccOffPath] (as the OUTER half of its hollow frame ring).
void _addBadgeOutline(Path path, double s) {
  path
    ..moveTo(464 * s, 64 * s)
    ..lineTo(48 * s, 64 * s)
    ..cubicTo(21.5 * s, 64 * s, 0 * s, 85.5 * s, 0 * s, 112 * s)
    ..lineTo(0 * s, 400 * s)
    ..cubicTo(0 * s, 426.5 * s, 21.5 * s, 448 * s, 48 * s, 448 * s)
    ..lineTo(464 * s, 448 * s)
    ..cubicTo(490.5 * s, 448 * s, 512 * s, 426.5 * s, 512 * s, 400 * s)
    ..lineTo(512 * s, 112 * s)
    ..cubicTo(512 * s, 85.5 * s, 490.5 * s, 64 * s, 464 * s, 64 * s)
    ..close();
}

/// `Icons.ccOn` — solid badge (evenOdd: [_addBadgeOutline] filled, minus the 2 "C" holes below).
Path _ccOnPath(double s) {
  final path = Path()..fillType = PathFillType.evenOdd;
  _addBadgeOutline(path, s);

  // Left "C" hole.
  path
    ..moveTo(218.1 * s, 287.7 * s)
    ..cubicTo(220.9 * s, 285.2 * s, 225.2 * s, 285.6 * s, 227.3 * s, 288.6 * s)
    ..lineTo(246.8 * s, 316.3 * s)
    ..cubicTo(248.5 * s, 318.7 * s, 248.3 * s, 321.9 * s, 246.3 * s, 324 * s)
    ..cubicTo(192.7 * s, 380.8 * s, 73.5 * s, 356.1 * s, 73.5 * s, 256.1 * s)
    ..cubicTo(73.5 * s, 158.8 * s, 195.2 * s, 136.6 * s, 246 * s, 186 * s)
    ..cubicTo(248.1 * s, 188 * s, 248.5 * s, 189.2 * s, 247 * s, 191.7 * s)
    ..lineTo(229.5 * s, 222.2 * s)
    ..cubicTo(227.6 * s, 225.3 * s, 223.3 * s, 226.2 * s, 220.4 * s, 223.9 * s)
    ..cubicTo(179.6 * s, 191.9 * s, 125.8 * s, 209 * s, 125.8 * s, 255.1 * s)
    ..cubicTo(125.9 * s, 303.1 * s, 176.9 * s, 325.6 * s, 218.1 * s, 287.7 * s)
    ..close();

  // Right "C" hole (left "C" shifted +190.4 on x).
  path
    ..moveTo(408.5 * s, 287.7 * s)
    ..cubicTo(411.3 * s, 285.2 * s, 415.6 * s, 285.6 * s, 417.7 * s, 288.6 * s)
    ..lineTo(437.2 * s, 316.3 * s)
    ..cubicTo(438.9 * s, 318.7 * s, 438.7 * s, 321.9 * s, 436.7 * s, 324 * s)
    ..cubicTo(383.2 * s, 380.9 * s, 264 * s, 356.1 * s, 264 * s, 256.1 * s)
    ..cubicTo(264 * s, 158.8 * s, 385.7 * s, 136.6 * s, 436.5 * s, 186 * s)
    ..cubicTo(438.6 * s, 188 * s, 439 * s, 189.2 * s, 437.5 * s, 191.7 * s)
    ..lineTo(420 * s, 222.2 * s)
    ..cubicTo(418.1 * s, 225.3 * s, 413.8 * s, 226.2 * s, 410.9 * s, 223.9 * s)
    ..cubicTo(370.1 * s, 191.9 * s, 316.3 * s, 209 * s, 316.3 * s, 255.1 * s)
    ..cubicTo(316.3 * s, 303.1 * s, 367.3 * s, 325.6 * s, 408.5 * s, 287.7 * s)
    ..close();

  return path;
}

/// `Icons.ccOff` — hollow badge frame (outer + inner ring) with the 2 "C" shapes filled solid
/// inside the hollow middle (evenOdd across all 4 subpaths).
Path _ccOffPath(double s) {
  final path = Path()..fillType = PathFillType.evenOdd;
  _addBadgeOutline(path, s);

  // Inner frame boundary — together with the outer outline above, evenOdd renders the area
  // between them (the border ring) filled, and the hollow middle unfilled.
  path
    ..moveTo(458 * s, 400 * s)
    ..lineTo(54 * s, 400 * s)
    ..cubicTo(50.7 * s, 400 * s, 48 * s, 397.3 * s, 48 * s, 394 * s)
    ..lineTo(48 * s, 118 * s)
    ..cubicTo(48 * s, 114.7 * s, 50.7 * s, 112 * s, 54 * s, 112 * s)
    ..lineTo(458 * s, 112 * s)
    ..cubicTo(461.3 * s, 112 * s, 464 * s, 114.7 * s, 464 * s, 118 * s)
    ..lineTo(464 * s, 394 * s)
    ..cubicTo(464 * s, 397.3 * s, 461.3 * s, 400 * s, 458 * s, 400 * s)
    ..close();

  // Left "C" — a 3rd crossing inside the (otherwise unfilled) hollow middle renders it solid.
  path
    ..moveTo(246.9 * s, 314.3 * s)
    ..cubicTo(248.6 * s, 316.7 * s, 248.4 * s, 319.9 * s, 246.4 * s, 322 * s)
    ..cubicTo(192.8 * s, 378.8 * s, 73.6 * s, 354.1 * s, 73.6 * s, 254.1 * s)
    ..cubicTo(73.6 * s, 156.8 * s, 195.3 * s, 134.6 * s, 246.1 * s, 184 * s)
    ..cubicTo(248.2 * s, 186 * s, 248.6 * s, 187.2 * s, 247.1 * s, 189.7 * s)
    ..lineTo(229.6 * s, 220.2 * s)
    ..cubicTo(227.7 * s, 223.3 * s, 223.4 * s, 224.2 * s, 220.5 * s, 221.9 * s)
    ..cubicTo(179.7 * s, 189.9 * s, 125.9 * s, 207 * s, 125.9 * s, 253.1 * s)
    ..cubicTo(125.9 * s, 301.1 * s, 176.9 * s, 323.6 * s, 218.1 * s, 285.7 * s)
    ..cubicTo(220.9 * s, 283.2 * s, 225.2 * s, 283.6 * s, 227.3 * s, 286.6 * s)
    ..lineTo(246.9 * s, 314.3 * s)
    ..close();

  // Right "C" (left "C" shifted +190.4 on x).
  path
    ..moveTo(437.3 * s, 314.3 * s)
    ..cubicTo(439 * s, 316.7 * s, 438.8 * s, 319.9 * s, 436.8 * s, 322 * s)
    ..cubicTo(383.2 * s, 378.9 * s, 264 * s, 354.1 * s, 264 * s, 254.1 * s)
    ..cubicTo(264 * s, 156.8 * s, 385.7 * s, 134.6 * s, 436.5 * s, 184 * s)
    ..cubicTo(438.6 * s, 186 * s, 439 * s, 187.2 * s, 437.5 * s, 189.7 * s)
    ..lineTo(420 * s, 220.2 * s)
    ..cubicTo(418.1 * s, 223.3 * s, 413.8 * s, 224.2 * s, 410.9 * s, 221.9 * s)
    ..cubicTo(370.1 * s, 189.9 * s, 316.3 * s, 207 * s, 316.3 * s, 253.1 * s)
    ..cubicTo(316.3 * s, 301.1 * s, 367.3 * s, 323.6 * s, 408.5 * s, 285.7 * s)
    ..cubicTo(411.3 * s, 283.2 * s, 415.6 * s, 283.6 * s, 417.7 * s, 286.6 * s)
    ..lineTo(437.3 * s, 314.3 * s)
    ..close();

  return path;
}

/// `Icons.ccUnavailable` — 24×22 viewBox, non-uniform [sx]/[sy] (see [CcGlyph] doc). Frame ring
/// (2 subpaths) + two "unavailable source" icon shapes (2 subpaths), evenOdd throughout.
Path _ccUnavailablePath(double sx, double sy) {
  final path = Path()..fillType = PathFillType.evenOdd;

  // Outer frame boundary.
  path
    ..moveTo(21.3333 * sx, 1.375 * sy)
    ..lineTo(2.66667 * sx, 1.375 * sy)
    ..cubicTo(1.19375 * sx, 1.375 * sy, 0 * sx, 2.60605 * sy, 0 * sx, 4.125 * sy)
    ..lineTo(0 * sx, 17.875 * sy)
    ..cubicTo(0 * sx, 19.3939 * sy, 1.19375 * sx, 20.625 * sy, 2.66667 * sx, 20.625 * sy)
    ..lineTo(21.3333 * sx, 20.625 * sy)
    ..cubicTo(22.8063 * sx, 20.625 * sy, 24 * sx, 19.3939 * sy, 24 * sx, 17.875 * sy)
    ..lineTo(24 * sx, 4.125 * sy)
    ..cubicTo(24 * sx, 2.60605 * sy, 22.8042 * sx, 1.375 * sy, 21.3333 * sx, 1.375 * sy)
    ..close();

  // Inner frame boundary — with the outer boundary, evenOdd renders the border ring.
  path
    ..moveTo(22 * sx, 17.875 * sy)
    ..cubicTo(22 * sx, 18.2541 * sy, 21.7009 * sx, 18.5625 * sy, 21.3333 * sx, 18.5625 * sy)
    ..lineTo(2.66667 * sx, 18.5625 * sy)
    ..cubicTo(2.29908 * sx, 18.5625 * sy, 2 * sx, 18.2541 * sy, 2 * sx, 17.875 * sy)
    ..lineTo(2 * sx, 4.125 * sy)
    ..cubicTo(2 * sx, 3.74593 * sy, 2.29908 * sx, 3.4375 * sy, 2.66667 * sx, 3.4375 * sy)
    ..lineTo(21.3333 * sx, 3.4375 * sy)
    ..cubicTo(21.7009 * sx, 3.4375 * sy, 22 * sx, 3.74593 * sy, 22 * sx, 4.125 * sy)
    ..lineTo(22 * sx, 17.875 * sy)
    ..close();

  // Left icon shape.
  path
    ..moveTo(9.85417 * sx, 9.54336 * sy)
    ..cubicTo(10.2448 * sx, 9.94619 * sy, 10.8775 * sx, 9.94619 * sy, 11.2683 * sx, 9.54336 * sy)
    ..cubicTo(11.659 * sx, 9.14053 * sy, 11.659 * sx, 8.48805 * sy, 11.2683 * sx, 8.085 * sy)
    ..cubicTo(9.70833 * sx, 6.47625 * sy, 7.17208 * sx, 6.47625 * sy, 5.61417 * sx, 8.085 * sy)
    ..cubicTo(4.85417 * sx, 8.86016 * sy, 4.4375 * sx, 9.9 * sy, 4.4375 * sx, 11 * sy)
    ..cubicTo(4.4375 * sx, 12.1 * sy, 4.81667 * sx, 13.1377 * sy, 5.60917 * sx, 13.9167 * sy)
    ..cubicTo(6.38917 * sx, 14.7211 * sy, 7.4125 * sx, 15.1233 * sy, 8.43708 * sx, 15.1233 * sy)
    ..cubicTo(9.46167 * sx, 15.1233 * sy, 10.4854 * sx, 14.7211 * sy, 11.265 * sx, 13.9167 * sy)
    ..cubicTo(11.6556 * sx, 13.5139 * sy, 11.6556 * sx, 12.8614 * sy, 11.265 * sx, 12.4584 * sy)
    ..cubicTo(10.8744 * sx, 12.0555 * sy, 10.2417 * sx, 12.0555 * sy, 9.85083 * sx, 12.4584 * sy)
    ..cubicTo(9.07208 * sx, 13.2627 * sy, 7.80125 * sx, 13.2627 * sy, 7.02292 * sx, 12.4584 * sy)
    ..cubicTo(6.64583 * sx, 12.0699 * sy, 6.4375 * sx, 11.55 * sy, 6.4375 * sx, 11 * sy)
    ..cubicTo(6.4375 * sx, 10.45 * sy, 6.64583 * sx, 9.93094 * sy, 7.02333 * sx, 9.54164 * sy)
    ..cubicTo(7.80417 * sx, 8.73555 * sy, 9.075 * sx, 8.73555 * sy, 9.85417 * sx, 9.54336 * sy)
    ..close();

  // Right icon shape (left shape shifted +8 on x).
  path
    ..moveTo(17.8542 * sx, 9.54336 * sy)
    ..cubicTo(18.2448 * sx, 9.94619 * sy, 18.8775 * sx, 9.94619 * sy, 19.2683 * sx, 9.54336 * sy)
    ..cubicTo(19.659 * sx, 9.14053 * sy, 19.659 * sx, 8.48805 * sy, 19.2683 * sx, 8.085 * sy)
    ..cubicTo(17.7083 * sx, 6.47625 * sy, 15.1721 * sx, 6.47625 * sy, 13.6142 * sx, 8.085 * sy)
    ..cubicTo(12.8542 * sx, 8.86016 * sy, 12.4375 * sx, 9.9 * sy, 12.4375 * sx, 11 * sy)
    ..cubicTo(12.4375 * sx, 12.1 * sy, 12.8167 * sx, 13.1377 * sy, 13.6092 * sx, 13.9167 * sy)
    ..cubicTo(14.3892 * sx, 14.7211 * sy, 15.4125 * sx, 15.1233 * sy, 16.4371 * sx, 15.1233 * sy)
    ..cubicTo(17.4617 * sx, 15.1233 * sy, 18.4854 * sx, 14.7211 * sy, 19.265 * sx, 13.9167 * sy)
    ..cubicTo(19.6556 * sx, 13.5139 * sy, 19.6556 * sx, 12.8614 * sy, 19.265 * sx, 12.4584 * sy)
    ..cubicTo(18.8744 * sx, 12.0555 * sy, 18.2417 * sx, 12.0555 * sy, 17.8508 * sx, 12.4584 * sy)
    ..cubicTo(17.0721 * sx, 13.2627 * sy, 15.8012 * sx, 13.2627 * sy, 15.0229 * sx, 12.4584 * sy)
    ..cubicTo(14.6458 * sx, 12.0699 * sy, 14.4375 * sx, 11.55 * sy, 14.4375 * sx, 11 * sy)
    ..cubicTo(14.4375 * sx, 10.45 * sy, 14.6458 * sx, 9.93094 * sy, 15.0233 * sx, 9.54164 * sy)
    ..cubicTo(15.8042 * sx, 8.73555 * sy, 17.075 * sx, 8.73555 * sy, 17.8542 * sx, 9.54336 * sy)
    ..close();

  return path;
}
