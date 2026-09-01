import 'package:flutter/widgets.dart';

// win_glyph.dart — shared trophy/gift glyph Path (family-2 feed-win).
//
// Promoted here (rb-flutter-live-activity-sheet, design.md D4) from what was
// originally a `win_entry.dart`-PRIVATE definition (`_WinTrophyGlyphPainter` +
// `_winGlyphOuterPath` / `_winGlyphInnerPath`), so a second consumer
// (`ActivitySheetView`, `activity_sheet.dart`) can reuse the SAME ported SVG
// coordinate data instead of re-porting it a third time. This exact coordinate
// data was already precisely ported once (rb-flutter-win-entry-restyle, R24),
// including a known `PathFillType.evenOdd` pitfall for the inner cutout's 4
// overlapping subpaths — a second manual transcription would risk
// reintroducing it.
//
// Consumers: `WinEntryView` (`win_entry.dart`, BOTH `win` and `activity`
// variants) and `ActivitySheetView` (`activity_sheet.dart`).
//
// NOTE: `WinClaimSheetView`'s (`win_claim_sheet.dart`) badge glyph is a generic
// `Icon(Icons.card_giftcard)`, NOT this ported Path — it never adopted this
// asset (a pre-existing platform divergence, not introduced by this change).
// `rb-flutter-live-activity-sheet` proposal.md's non-goals explicitly exclude
// touching `WinClaimSheetView`, so that file is left as-is; "shared" here means
// shared between `WinEntryView` and `ActivitySheetView` only.

/// The glyph's native SVG viewBox (`viewBox="0 0 200 200"`) — the two `Path`s
/// below are authored verbatim in this coordinate space and scaled down to the
/// caller's requested paint [Size] at paint time.
const double winGlyphViewBoxSize = 200;

/// Trophy/gift glyph outer-silhouette fill (`fill={giftFill}` in the design) —
/// hardcoded, NOT `theme.accent` (a deliberate divergence from this module's
/// usual accent-coloring convention; carried from `win_entry.dart` design.md D-2).
const Color winGlyphOuterColor = Color(0xFFF03246);

/// Trophy/gift glyph inner-cutout fill (`fill="#FFFFFF"` in the design).
const Color winGlyphInnerColor = Color(0xFFFFFFFF);

/// Paints the design's two-path trophy/gift glyph (`moments.jsx` · `LBWinEntry`,
/// `viewBox 0 0 200 200`) — an outer silhouette with an inner cutout on top,
/// both `evenodd` filled (mirrors the SVG's `fillRule="evenodd"`; the inner
/// path's 4 subpaths need evenodd for the overlapping regions to render as
/// cutouts rather than solid fill). Shared by `WinEntryView` and
/// `ActivitySheetView` — see file header.
///
/// [outerColor] / [innerColor] default to the SAME hardcoded fills
/// `WinEntryView` uses ([winGlyphOuterColor] `#F03246` / [winGlyphInnerColor]
/// white — NOT `theme.accent`, a deliberate divergence, see their docs), so
/// `WinEntryView`'s existing `const WinTrophyGlyphPainter()` call site is
/// UNCHANGED in appearance. `ActivitySheetView`'s badge overrides [outerColor]
/// to `theme.accent` (design.md D4) — same Path, different tint.
class WinTrophyGlyphPainter extends CustomPainter {
  const WinTrophyGlyphPainter({
    this.outerColor = winGlyphOuterColor,
    this.innerColor = winGlyphInnerColor,
  });

  /// Outer-silhouette fill. Defaults to [winGlyphOuterColor].
  final Color outerColor;

  /// Inner-cutout fill. Defaults to [winGlyphInnerColor].
  final Color innerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / winGlyphViewBoxSize;
    canvas.save();
    canvas.scale(k, size.height / winGlyphViewBoxSize);

    final outerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = outerColor;
    final innerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = innerColor;

    canvas.drawPath(_winGlyphOuterPath, outerPaint);
    canvas.drawPath(_winGlyphInnerPath, innerPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WinTrophyGlyphPainter oldDelegate) =>
      oldDelegate.outerColor != outerColor || oldDelegate.innerColor != innerColor;
}

// MARK: - Glyph path data — mechanically ported two-path gift/trophy glyph
//
// Design: rb-flutter-win-entry-restyle design.md D-1. Coordinates are copied
// AS-IS from `design/templates/minimal/moments.jsx`'s `LBWinEntry` two
// `<path d="...">` strings (`viewBox 0 0 200 200`) via a one-off tokenizer
// script (discarded after use) that machine-translated each `M`/`L`/`C`/`Z` SVG
// path command into the matching Dart `Path` builder call — neither string
// contains an `a`/`A` elliptical-arc command, so no arc→bezier conversion
// (`icon-authoring.md` rule 1) is needed. The generated segment counts were
// cross-checked against the original `d` strings' command counts and against
// the already-landed iOS port (`WinEntryGiftGlyph`, `WinEntryView.swift`) —
// both agree: outer = 1 M + 68 C + 8 L + 1 Z, inner = 4 M + 48 C + 18 L + 4 Z.

/// Outer silhouette — a single closed subpath.
final Path _winGlyphOuterPath = Path()
  ..fillType = PathFillType.evenOdd
  ..moveTo(24.78, 199.49)
  ..cubicTo(24.46, 199.22, 23.99, 199.0, 23.75, 199.0)
  ..cubicTo(23.19, 199.0, 21.24, 198.09, 19.75, 197.14)
  ..cubicTo(18.15, 196.11, 15.83, 193.84, 14.89, 192.38)
  ..cubicTo(13.39, 190.04, 13.25, 189.77, 12.56, 187.82)
  ..lineTo(11.88, 185.88)
  ..lineTo(11.81, 139.62)
  ..lineTo(11.74, 93.37)
  ..lineTo(10.32, 92.62)
  ..cubicTo(6.32, 90.52, 3.64, 87.94, 2.05, 84.66)
  ..cubicTo(1.47, 83.48, 1.0, 82.3, 1.0, 82.04)
  ..cubicTo(1.0, 81.78, 0.77, 81.28, 0.5, 80.93)
  ..cubicTo(0.02, 80.32, 0.0, 79.92, 0.0, 70.42)
  ..cubicTo(0.0, 62.18, 0.06, 60.53, 0.35, 60.42)
  ..cubicTo(0.54, 60.34, 0.78, 59.91, 0.88, 59.45)
  ..cubicTo(1.73, 55.46, 5.74, 50.72, 10.0, 48.69)
  ..cubicTo(13.4, 47.07, 12.63, 47.15, 27.37, 47.01)
  ..cubicTo(40.18, 46.88, 40.87, 46.85, 40.96, 46.42)
  ..cubicTo(41.0, 46.17, 40.85, 45.75, 40.61, 45.48)
  ..cubicTo(40.08, 44.89, 39.78, 44.39, 38.68, 42.12)
  ..cubicTo(37.48, 39.69, 37.0, 38.59, 37.0, 38.32)
  ..cubicTo(37.0, 38.19, 36.78, 37.36, 36.51, 36.48)
  ..cubicTo(35.43, 32.95, 35.48, 25.46, 36.61, 21.62)
  ..cubicTo(38.41, 15.53, 41.86, 10.34, 46.63, 6.53)
  ..cubicTo(47.59, 5.76, 48.61, 4.99, 48.88, 4.82)
  ..cubicTo(51.93, 2.96, 54.37, 1.88, 57.08, 1.21)
  ..cubicTo(58.2, 0.93, 59.37, 0.54, 59.68, 0.35)
  ..cubicTo(60.49, -0.16, 70.17, -0.14, 70.85, 0.37)
  ..cubicTo(71.1, 0.57, 71.95, 0.85, 72.72, 1.01)
  ..cubicTo(76.52, 1.76, 80.21, 3.7, 83.48, 6.67)
  ..cubicTo(85.08, 8.11, 88.41, 12.13, 89.37, 13.78)
  ..cubicTo(89.65, 14.24, 90.23, 15.24, 90.67, 16.0)
  ..cubicTo(91.75, 17.84, 93.99, 22.43, 95.51, 25.88)
  ..cubicTo(95.92, 26.8, 96.14, 27.35, 97.5, 30.75)
  ..cubicTo(97.78, 31.44, 98.22, 32.53, 98.48, 33.19)
  ..cubicTo(98.75, 33.84, 99.07, 34.71, 99.19, 35.12)
  ..cubicTo(99.36, 35.69, 99.57, 35.88, 100.01, 35.88)
  ..cubicTo(100.46, 35.88, 100.67, 35.69, 100.84, 35.12)
  ..cubicTo(100.96, 34.71, 101.27, 33.91, 101.53, 33.35)
  ..cubicTo(101.79, 32.78, 102.0, 32.22, 102.01, 32.1)
  ..cubicTo(102.01, 31.98, 102.23, 31.43, 102.5, 30.88)
  ..cubicTo(102.77, 30.32, 102.99, 29.73, 102.99, 29.55)
  ..cubicTo(103.0, 29.37, 103.22, 28.81, 103.48, 28.3)
  ..cubicTo(103.75, 27.79, 104.27, 26.64, 104.64, 25.75)
  ..cubicTo(105.01, 24.86, 105.68, 23.34, 106.13, 22.38)
  ..cubicTo(106.58, 21.41, 107.02, 20.46, 107.1, 20.25)
  ..cubicTo(107.18, 20.04, 107.76, 18.98, 108.37, 17.88)
  ..cubicTo(108.99, 16.77, 109.64, 15.59, 109.81, 15.25)
  ..cubicTo(110.84, 13.2, 114.1, 8.93, 116.04, 7.1)
  ..cubicTo(119.07, 4.23, 122.94, 2.07, 126.62, 1.2)
  ..cubicTo(127.86, 0.91, 129.05, 0.52, 129.27, 0.33)
  ..cubicTo(129.57, 0.08, 130.86, 0.0, 134.65, 0.0)
  ..cubicTo(139.15, 0.0, 139.74, 0.05, 140.63, 0.5)
  ..cubicTo(141.16, 0.78, 141.85, 1.0, 142.15, 1.0)
  ..cubicTo(143.57, 1.0, 148.42, 3.05, 151.19, 4.83)
  ..cubicTo(155.32, 7.47, 159.24, 11.96, 161.49, 16.62)
  ..cubicTo(165.93, 25.84, 165.3, 36.56, 159.81, 44.94)
  ..cubicTo(159.34, 45.66, 159.01, 46.42, 159.09, 46.62)
  ..cubicTo(159.21, 46.93, 161.21, 46.99, 172.68, 47.06)
  ..cubicTo(185.71, 47.15, 186.17, 47.16, 187.62, 47.69)
  ..cubicTo(189.35, 48.31, 190.95, 49.1, 192.38, 50.03)
  ..cubicTo(193.55, 50.81, 196.23, 53.5, 197.07, 54.76)
  ..cubicTo(197.91, 56.01, 199.0, 58.38, 199.0, 58.95)
  ..cubicTo(199.0, 59.22, 199.22, 59.72, 199.5, 60.07)
  ..cubicTo(199.98, 60.68, 200.0, 61.08, 200.0, 70.57)
  ..cubicTo(200.0, 78.84, 199.94, 80.49, 199.64, 80.74)
  ..cubicTo(199.44, 80.9, 199.21, 81.39, 199.11, 81.83)
  ..cubicTo(198.27, 85.83, 194.71, 90.0, 190.02, 92.5)
  ..lineTo(188.38, 93.38)
  ..lineTo(188.25, 139.75)
  ..lineTo(188.12, 186.12)
  ..lineTo(187.43, 187.83)
  ..cubicTo(185.99, 191.38, 184.41, 193.71, 182.13, 195.61)
  ..cubicTo(180.04, 197.36, 179.02, 197.9, 175.31, 199.26)
  ..cubicTo(174.87, 199.43, 174.5, 199.66, 174.5, 199.78)
  ..cubicTo(174.5, 199.91, 142.62, 200.0, 99.94, 199.99)
  ..cubicTo(26.17, 199.98, 25.37, 199.98, 24.78, 199.49)
  ..close();

/// Inner cutouts — 4 independent closed subpaths (trophy/gift line detail,
/// combined with [PathFillType.evenOdd] so overlapping regions render as
/// negative-space cutouts through [_winGlyphOuterPath]).
final Path _winGlyphInnerPath = Path()
  ..fillType = PathFillType.evenOdd
  ..moveTo(76.75, 153.3)
  ..cubicTo(76.75, 117.31, 76.68, 106.53, 76.45, 106.3)
  ..cubicTo(76.22, 106.07, 68.66, 106.0, 43.95, 106.0)
  ..lineTo(11.75, 106.0)
  ..lineTo(11.75, 99.62)
  ..lineTo(11.75, 93.24)
  ..lineTo(12.44, 93.4)
  ..cubicTo(12.82, 93.5, 13.35, 93.69, 13.62, 93.85)
  ..cubicTo(14.32, 94.23, 75.53, 94.39, 76.25, 94.0)
  ..cubicTo(76.74, 93.74, 76.75, 93.45, 76.81, 76.43)
  ..lineTo(76.88, 59.12)
  ..lineTo(82.5, 59.12)
  ..lineTo(88.12, 59.12)
  ..lineTo(88.19, 129.56)
  ..lineTo(88.25, 200.0)
  ..lineTo(82.5, 200.0)
  ..lineTo(76.75, 200.0)
  ..lineTo(76.75, 153.3)
  ..close()
  ..moveTo(111.75, 129.9)
  ..cubicTo(111.75, 91.34, 111.82, 59.61, 111.9, 59.4)
  ..cubicTo(112.03, 59.05, 112.76, 59.0, 117.5, 59.0)
  ..cubicTo(121.81, 59.0, 123.0, 59.07, 123.22, 59.34)
  ..cubicTo(123.43, 59.59, 123.51, 64.28, 123.49, 76.65)
  ..cubicTo(123.48, 92.66, 123.5, 93.64, 123.93, 93.94)
  ..cubicTo(124.29, 94.21, 130.1, 94.25, 155.12, 94.19)
  ..cubicTo(183.09, 94.11, 185.97, 94.06, 186.88, 93.69)
  ..cubicTo(187.43, 93.46, 187.99, 93.27, 188.12, 93.26)
  ..cubicTo(188.29, 93.25, 188.35, 95.49, 188.3, 99.62)
  ..lineTo(188.23, 106.0)
  ..lineTo(156.01, 106.0)
  ..cubicTo(136.42, 106.0, 123.72, 106.09, 123.64, 106.23)
  ..cubicTo(123.56, 106.36, 123.49, 127.51, 123.5, 153.23)
  ..lineTo(123.5, 200.0)
  ..lineTo(117.63, 200.0)
  ..lineTo(111.75, 200.0)
  ..lineTo(111.75, 129.9)
  ..close()
  ..moveTo(62.62, 46.84)
  ..cubicTo(59.24, 46.11, 57.49, 45.43, 55.25, 43.96)
  ..cubicTo(51.31, 41.38, 48.78, 37.67, 47.75, 32.96)
  ..cubicTo(47.13, 30.08, 47.12, 28.92, 47.74, 25.92)
  ..cubicTo(49.05, 19.56, 53.24, 14.87, 59.64, 12.63)
  ..cubicTo(61.45, 12.0, 61.93, 11.94, 65.12, 11.95)
  ..cubicTo(68.01, 11.95, 68.93, 12.05, 70.38, 12.5)
  ..cubicTo(74.59, 13.82, 77.44, 16.52, 80.8, 22.38)
  ..cubicTo(82.15, 24.73, 83.54, 27.72, 85.65, 32.81)
  ..cubicTo(86.0, 33.67, 86.44, 34.71, 86.62, 35.12)
  ..cubicTo(86.79, 35.54, 87.24, 36.66, 87.61, 37.62)
  ..cubicTo(87.98, 38.59, 88.45, 39.73, 88.64, 40.16)
  ..cubicTo(88.84, 40.6, 89.0, 41.03, 89.0, 41.12)
  ..cubicTo(89.0, 41.22, 89.16, 41.65, 89.35, 42.09)
  ..cubicTo(90.68, 45.04, 91.04, 46.01, 90.96, 46.41)
  ..cubicTo(90.87, 46.86, 90.28, 46.88, 77.0, 46.91)
  ..cubicTo(69.37, 46.93, 62.9, 46.9, 62.62, 46.84)
  ..close()
  ..moveTo(109.09, 46.62)
  ..cubicTo(109.0, 46.39, 109.19, 45.63, 109.5, 44.92)
  ..cubicTo(109.81, 44.21, 110.26, 43.12, 110.5, 42.5)
  ..cubicTo(111.06, 41.07, 111.79, 39.25, 112.5, 37.5)
  ..cubicTo(112.81, 36.74, 113.28, 35.56, 113.56, 34.88)
  ..cubicTo(113.83, 34.19, 114.2, 33.29, 114.38, 32.88)
  ..cubicTo(114.57, 32.46, 115.07, 31.28, 115.5, 30.25)
  ..cubicTo(117.07, 26.48, 120.08, 20.73, 121.48, 18.83)
  ..cubicTo(124.03, 15.36, 126.18, 13.68, 129.44, 12.6)
  ..cubicTo(131.14, 12.03, 131.8, 11.96, 134.88, 11.95)
  ..cubicTo(137.83, 11.94, 138.63, 12.03, 140.0, 12.49)
  ..cubicTo(143.57, 13.68, 146.79, 15.81, 148.81, 18.29)
  ..cubicTo(150.2, 19.99, 151.7, 23.1, 152.25, 25.42)
  ..cubicTo(153.89, 32.33, 151.02, 39.73, 145.11, 43.81)
  ..cubicTo(143.63, 44.83, 142.0, 45.6, 139.75, 46.32)
  ..cubicTo(138.2, 46.82, 137.49, 46.84, 123.68, 46.93)
  ..cubicTo(110.55, 47.01, 109.23, 46.99, 109.09, 46.62)
  ..close();
