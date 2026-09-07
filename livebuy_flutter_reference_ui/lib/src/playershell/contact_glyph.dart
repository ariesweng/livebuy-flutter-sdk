import 'package:flutter/widgets.dart';

// MARK: - ContactGlyph — hand-drawn dual speech-bubble + question-mark glyph
//                        (design `Icons.contact`)
//
// Design: `design/shared/icons.jsx` `Icons.contact` — single FILL path (24px viewBox).
// 4 subpaths: the small (trailing, upper-right) speech bubble; the large (leading,
// lower-left) speech bubble; the question-mark's dot; the question-mark's hook stroke
// (all drawn as filled shapes — the design has no stroke elements here). Straight lines
// + cubic beziers only (no arcs).
//
// Ported from iOS `ContactGlyph.swift` (`ios/Sources/LivebuyReferenceUI/Glyphs/
// ContactGlyph.swift`, rb-ios-icon-parity, 2026-08-25 redesign). `addCurve(to:control1:
// control2:)` maps to Dart `Path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy)`
// (same control1→control2→end argument order as the SwiftUI call). `move(to:)` →
// `moveTo()`; `closeSubpath()` → `close()`. Pure fill — all 4 subpaths live in ONE
// `Path` object (Dart's `Path.moveTo` starts a new subpath within the same object,
// same as SwiftUI's `Path { p in ... }` builder), painted with a single
// `canvas.drawPath(path, fillPaint)` call.
//
// Flutter parity of iOS `ContactGlyph` / Android shared `IconGlyphs.ContactGlyph`
// (`rb-flutter-icon-parity-operation-rail-batch`) — replaces `Icons.chat_bubble` /
// `Icons.chat_bubble_outline` at every 「聯繫商家」/service-link semantic slot in
// `flutter-reference-ui` (`OperationRailView`'s `serviceLink` pill, the「更多」sheet's
// 客服 slot in `player_shell_view.dart`, and `VideoInfoPanelView`'s footer button).

/// The self-drawn dual speech-bubble + question-mark glyph. [size] is the square edge.
class ContactGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const ContactGlyph({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ContactGlyphPainter(color)),
    );
  }
}

class _ContactGlyphPainter extends CustomPainter {
  final Color color;
  _ContactGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();

    // Subpath 1 — small speech bubble (upper-right).
    path.moveTo(22.4851 * s, 18.6388 * s);
    path.cubicTo(23.4301 * s, 17.5213 * s, 24.0001 * s, 16.1225 * s, 24.0001 * s, 14.6 * s);
    path.cubicTo(24.0001 * s, 10.955 * s, 20.7751 * s, 8 * s, 16.8001 * s, 8 * s);
    path.cubicTo(16.7883 * s, 8 * s, 16.7769 * s, 8.0015 * s, 16.7651 * s, 8.0016 * s);
    path.cubicTo(16.7813 * s, 8.1988 * s, 16.8001 * s, 8.3975 * s, 16.8001 * s, 8.6 * s);
    path.cubicTo(16.8001 * s, 12.2983 * s, 13.8121 * s, 15.395 * s, 9.8213 * s, 16.1938 * s);
    path.cubicTo(10.6013 * s, 19.0662 * s, 13.3913 * s, 21.2 * s, 16.8001 * s, 21.2 * s);
    path.cubicTo(18.0634 * s, 21.2 * s, 19.2496 * s, 20.8997 * s, 20.2819 * s, 20.3757 * s);
    path.cubicTo(21.1951 * s, 20.825 * s, 22.3538 * s, 21.2 * s, 23.7113 * s, 21.2 * s);
    path.cubicTo(23.826 * s, 21.2 * s, 23.9273 * s, 21.1353 * s, 23.9746 * s, 21.0273 * s);
    path.cubicTo(24.0207 * s, 20.9193 * s, 23.9993 * s, 20.7968 * s, 23.9205 * s, 20.714 * s);
    path.cubicTo(23.9101 * s, 20.7013 * s, 23.0963 * s, 19.8238 * s, 22.4851 * s, 18.6388 * s);
    path.close();

    // Subpath 2 — large speech bubble (leading, lower-left).
    path.moveTo(15.6001 * s, 8.6 * s);
    path.cubicTo(15.6001 * s, 4.955 * s, 12.1088 * s, 2 * s, 7.8001 * s, 2 * s);
    path.cubicTo(3.4913 * s, 2 * s, 0.0001 * s, 4.955 * s, 0.0001 * s, 8.6 * s);
    path.cubicTo(0.0001 * s, 10.0839 * s, 0.5858 * s, 11.4485 * s, 1.5627 * s, 12.5525 * s);
    path.cubicTo(0.9481 * s, 13.781 * s, 0.0916 * s, 14.702 * s, 0.0781 * s, 14.7155 * s);
    path.cubicTo(-0.0007 * s, 14.7982 * s, -0.0221 * s, 14.9208 * s, 0.024 * s, 15.0288 * s);
    path.cubicTo(0.0713 * s, 15.1363 * s, 0.1726 * s, 15.2 * s, 0.2873 * s, 15.2 * s);
    path.cubicTo(1.7254 * s, 15.2 * s, 2.9408 * s, 14.783 * s, 3.8776 * s, 14.2985 * s);
    path.cubicTo(5.0326 * s, 14.8663 * s, 6.3676 * s, 15.2 * s, 7.8001 * s, 15.2 * s);
    path.cubicTo(12.1088 * s, 15.2 * s, 15.6001 * s, 12.245 * s, 15.6001 * s, 8.6 * s);
    path.close();

    // Subpath 3 — question-mark dot.
    path.moveTo(7.8188 * s, 12.8 * s);
    path.cubicTo(7.3013 * s, 12.8 * s, 6.9001 * s, 12.3988 * s, 6.9001 * s, 11.8812 * s);
    path.cubicTo(6.9001 * s, 11.3649 * s, 7.3017 * s, 10.9636 * s, 7.8177 * s, 10.9636 * s);
    path.cubicTo(8.3341 * s, 10.9636 * s, 8.7353 * s, 11.3652 * s, 8.7353 * s, 11.8812 * s);
    path.cubicTo(8.7338 * s, 12.3988 * s, 8.3326 * s, 12.8 * s, 7.8188 * s, 12.8 * s);
    path.close();

    // Subpath 4 — question-mark hook.
    path.moveTo(9.7913 * s, 8.4275 * s);
    path.lineTo(8.5051 * s, 9.23 * s);
    path.lineTo(8.5051 * s, 9.2873 * s);
    path.cubicTo(8.5051 * s, 9.6601 * s, 8.1896 * s, 9.9755 * s, 7.817 * s, 9.9755 * s);
    path.cubicTo(7.4443 * s, 9.9755 * s, 7.1288 * s, 9.6612 * s, 7.1288 * s, 9.29 * s);
    path.lineTo(7.1288 * s, 8.8287 * s);
    path.cubicTo(7.1288 * s, 8.5994 * s, 7.2435 * s, 8.3701 * s, 7.4729 * s, 8.2265 * s);
    path.lineTo(9.1075 * s, 7.2515 * s);
    path.cubicTo(9.3076 * s, 7.1375 * s, 9.4238 * s, 6.935 * s, 9.4238 * s, 6.7062 * s);
    path.cubicTo(9.4238 * s, 6.3621 * s, 9.137 * s, 6.0755 * s, 8.7931 * s, 6.0755 * s);
    path.lineTo(7.3013 * s, 6.0755 * s);
    path.cubicTo(6.9571 * s, 6.0755 * s, 6.6706 * s, 6.3622 * s, 6.6706 * s, 6.7062 * s);
    path.cubicTo(6.6706 * s, 7.079 * s, 6.3551 * s, 7.3944 * s, 5.9824 * s, 7.3944 * s);
    path.cubicTo(5.6097 * s, 7.3944 * s, 5.2943 * s, 7.0789 * s, 5.2943 * s, 6.7062 * s);
    path.cubicTo(5.2951 * s, 5.5891 * s, 6.1838 * s, 4.7 * s, 7.3013 * s, 4.7 * s);
    path.lineTo(8.7923 * s, 4.7 * s);
    path.cubicTo(9.9113 * s, 4.7 * s, 10.8001 * s, 5.5891 * s, 10.8001 * s, 6.7062 * s);
    path.cubicTo(10.8001 * s, 7.3963 * s, 10.4288 * s, 8.0563 * s, 9.7913 * s, 8.4275 * s);
    path.close();

    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _ContactGlyphPainter old) => old.color != color;
}
